const express = require("express");
const prisma = require("../lib/prisma");
const upload = require("../lib/upload");
const { auth, isStaff } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { USER_SELECT, toUsers } = require("../lib/users");
const { notify } = require("../lib/notify");
const { audit } = require("../lib/audit");
const { asyncHandler, httpError, clampInt, str, optStr, lat, lon, parseDate } = require("../lib/util");

const router = express.Router();
const KINDS = ["LOST", "FOUND"];
const STATUSES = ["OPEN", "RESOLVED"];

async function shapeItems(rows, me) {
  const users = await toUsers(rows.map((r) => r.user));
  return rows.map((r, i) => ({
    id: r.id, kind: r.kind, title: r.title, description: r.description, category: r.category,
    wilaya: r.wilaya, city: r.city, latitude: r.latitude, longitude: r.longitude,
    imageUrl: r.imageUrl, contactHint: r.contactHint, status: r.status, createdAt: r.createdAt,
    user: users[i], mine: r.userId === me
  }));
}

const words = (s) => new Set(String(s || "").toLowerCase().split(/[\s,.;:!?()\-_/]+/).filter((w) => w.length > 2));

function score(a, b) {
  let s = 0;
  if (String(a.category).toLowerCase() === String(b.category).toLowerCase()) s += 2;
  if (a.wilaya === b.wilaya) s += 2;
  const wa = words(`${a.title} ${a.description}`);
  const wb = words(`${b.title} ${b.description}`);
  let common = 0;
  for (const w of wa) if (wb.has(w)) common++;
  s += Math.min(common, 4);
  return s;
}

async function findMatches(item, take = 10) {
  const candidates = await prisma.lostFound.findMany({
    where: {
      id: { not: item.id }, status: "OPEN", kind: item.kind === "LOST" ? "FOUND" : "LOST",
      OR: [{ category: item.category }, { wilaya: item.wilaya }]
    },
    include: { user: { select: USER_SELECT } }, orderBy: { createdAt: "desc" }, take: 80
  });
  return candidates
    .map((c) => ({ c, s: score(item, c) }))
    .filter((x) => x.s >= 3)
    .sort((x, y) => y.s - x.s)
    .slice(0, take)
    .map((x) => x.c);
}

router.get("/lost-found", auth, asyncHandler(async (req, res) => {
  const and = [];
  if (KINDS.includes(String(req.query.kind))) and.push({ kind: String(req.query.kind) });
  if (req.query.wilaya) and.push({ wilaya: String(req.query.wilaya) });
  if (req.query.category) and.push({ category: String(req.query.category) });
  if (req.query.mine === "1") and.push({ userId: req.user.id });
  else if (req.query.status !== "all") and.push({ status: "OPEN" });
  const q = str(req.query.q, 80);
  if (q) and.push({ OR: [{ title: { contains: q, mode: "insensitive" } }, { description: { contains: q, mode: "insensitive" } }] });
  const before = parseDate(req.query.before);
  if (before) and.push({ createdAt: { lt: before } });
  const rows = await prisma.lostFound.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 30, 100),
    include: { user: { select: USER_SELECT } }
  });
  res.json(await shapeItems(rows, req.user.id));
}));

router.post("/lost-found", auth, upload.single("image"), asyncHandler(async (req, res) => {
  const kind = KINDS.includes(String(req.body.kind)) ? String(req.body.kind) : "LOST";
  const title = str(req.body.title, 160);
  const description = str(req.body.description, 3000);
  const category = str(req.body.category, 40) || "other";
  const wilaya = str(req.body.wilaya, 60);
  if (!title || !description || !wilaya) throw httpError(400, "MISSING_FIELDS", "Missing fields");
  let imageUrl = null;
  if (req.file) imageUrl = (await storeUpload(req.file, { kinds: ["image"], ownerId: req.user.id })).url;
  const item = await prisma.lostFound.create({
    data: {
      userId: req.user.id, kind, title, description, category, wilaya, city: optStr(req.body.city, 80),
      latitude: lat(req.body.latitude), longitude: lon(req.body.longitude), imageUrl, contactHint: optStr(req.body.contactHint, 200)
    },
    include: { user: { select: USER_SELECT } }
  });
  // Tell both sides about strong matches.
  findMatches(item, 3).then((ms) => {
    for (const m of ms) {
      notify(m.userId, "lf_match", { title: item.title }, { data: { lostFoundId: item.id } });
      notify(item.userId, "lf_match", { title: m.title }, { data: { lostFoundId: m.id } });
    }
  }).catch(() => {});
  res.status(201).json((await shapeItems([item], req.user.id))[0]);
}));

router.get("/lost-found/:id", auth, asyncHandler(async (req, res) => {
  const item = await prisma.lostFound.findUnique({ where: { id: req.params.id }, include: { user: { select: USER_SELECT } } });
  if (!item) throw httpError(404, "NOT_FOUND", "Not found");
  const matches = await findMatches(item, 6);
  res.json({ item: (await shapeItems([item], req.user.id))[0], matches: await shapeItems(matches, req.user.id) });
}));

// kept for backward compatibility
router.get("/lost-found/matches/:id", auth, asyncHandler(async (req, res) => {
  const item = await prisma.lostFound.findUnique({ where: { id: req.params.id } });
  if (!item) throw httpError(404, "NOT_FOUND", "Not found");
  res.json(await shapeItems(await findMatches(item, 20), req.user.id));
}));

router.patch("/lost-found/:id", auth, asyncHandler(async (req, res) => {
  const item = await prisma.lostFound.findUnique({ where: { id: req.params.id } });
  if (!item) throw httpError(404, "NOT_FOUND", "Not found");
  if (item.userId !== req.user.id && !isStaff(req.user)) throw httpError(403, "FORBIDDEN", "Forbidden");
  const data = {};
  if (STATUSES.includes(String(req.body.status))) data.status = String(req.body.status);
  if (req.body.title !== undefined && str(req.body.title, 160)) data.title = str(req.body.title, 160);
  if (req.body.description !== undefined && str(req.body.description, 3000)) data.description = str(req.body.description, 3000);
  const row = await prisma.lostFound.update({ where: { id: item.id }, data, include: { user: { select: USER_SELECT } } });
  res.json((await shapeItems([row], req.user.id))[0]);
}));

router.delete("/lost-found/:id", auth, asyncHandler(async (req, res) => {
  const item = await prisma.lostFound.findUnique({ where: { id: req.params.id }, select: { id: true, userId: true } });
  if (!item) throw httpError(404, "NOT_FOUND", "Not found");
  if (item.userId !== req.user.id && !isStaff(req.user)) throw httpError(403, "FORBIDDEN", "Forbidden");
  await prisma.lostFound.delete({ where: { id: item.id } });
  if (item.userId !== req.user.id) await audit(req.user, "LOSTFOUND_DELETE", "LOSTFOUND", item.id);
  res.json({ ok: true });
}));

module.exports = router;
