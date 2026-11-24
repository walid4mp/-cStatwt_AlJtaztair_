const express = require("express");
const prisma = require("../lib/prisma");
const upload = require("../lib/upload");
const settings = require("../lib/settings");
const { auth, isStaff, staff } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { USER_SELECT, toUsers } = require("../lib/users");
const { notify, notifyStaff } = require("../lib/notify");
const { audit } = require("../lib/audit");
const { asyncHandler, httpError, clampInt, str, optStr, lat, lon, bool, parseDate, publicCoords, rateLimit } = require("../lib/util");

const router = express.Router();

const STATUSES = ["PENDING", "REVIEWED", "VERIFIED", "RESOLVED", "REJECTED"];
const PUBLIC_STATUSES = ["REVIEWED", "VERIFIED", "RESOLVED"];
const reportLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 20, key: (req) => (req.user ? req.user.id : req.ip) });

// What a normal user may see: reviewed reports (or everything but rejected when review is off) + their own.
async function visibility(user) {
  if (isStaff(user)) return {};
  const s = await settings.all();
  const base = settings.isTrue(s.requireReportReview)
    ? { status: { in: PUBLIC_STATUSES } }
    : { status: { not: "REJECTED" } };
  return { OR: [base, { reporterId: user.id }] };
}

function filters(query) {
  const and = [];
  if (query.wilaya) and.push({ wilaya: String(query.wilaya) });
  if (query.type) and.push({ type: String(query.type) });
  if (query.status && STATUSES.includes(String(query.status))) and.push({ status: String(query.status) });
  const q = str(query.q, 80);
  if (q) and.push({ OR: [{ title: { contains: q, mode: "insensitive" } }, { description: { contains: q, mode: "insensitive" } }, { city: { contains: q, mode: "insensitive" } }] });
  const before = parseDate(query.before);
  if (before) and.push({ createdAt: { lt: before } });
  return and;
}

async function shapeReports(rows, user) {
  const staffView = isStaff(user);
  const reporters = await toUsers(rows.map((r) => r.reporter), staffView);
  return rows.map((r, i) => {
    const mine = r.reporterId === user.id;
    const exact = mine || staffView;
    const plat = r.publicLatitude != null ? r.publicLatitude : (r.latitude != null ? Math.round(r.latitude * 100) / 100 : null);
    const plon = r.publicLongitude != null ? r.publicLongitude : (r.longitude != null ? Math.round(r.longitude * 100) / 100 : null);
    return {
      id: r.id,
      type: r.type,
      title: r.title,
      description: r.description,
      wilaya: r.wilaya,
      city: r.city,
      latitude: exact && r.latitude != null ? r.latitude : plat,
      longitude: exact && r.longitude != null ? r.longitude : plon,
      approximate: !exact,
      mediaUrl: r.mediaUrl,
      mediaType: r.mediaType,
      anonymous: r.anonymous,
      status: r.status,
      moderatorNote: exact ? r.moderatorNote : null,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      evidence: (r.evidence || []).map((e) => ({ id: e.id, url: e.url, type: e.type })),
      reporter: r.reporterId && (!r.anonymous || staffView || mine) ? reporters[i] : null,
      mine
    };
  });
}

const INCLUDE = { evidence: true, reporter: { select: USER_SELECT } };

router.get("/reports", auth, asyncHandler(async (req, res) => {
  const and = [await visibility(req.user), ...filters(req.query)];
  if (req.query.mine === "1" || req.query.mine === "true") and.push({ reporterId: req.user.id });
  const rows = await prisma.report.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 30, 100), include: INCLUDE
  });
  res.json(await shapeReports(rows, req.user));
}));

// Lightweight list for the map (only reports with coordinates).
router.get("/reports/map", auth, asyncHandler(async (req, res) => {
  const and = [await visibility(req.user), ...filters(req.query), { latitude: { not: null } }, { longitude: { not: null } }];
  const rows = await prisma.report.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 400, 1000),
    select: {
      id: true, type: true, title: true, status: true, wilaya: true, city: true, createdAt: true, mediaUrl: true, mediaType: true,
      reporterId: true, latitude: true, longitude: true, publicLatitude: true, publicLongitude: true
    }
  });
  const staffView = isStaff(req.user);
  res.json(rows.map((r) => {
    const exact = staffView || r.reporterId === req.user.id;
    return {
      id: r.id, type: r.type, title: r.title, status: r.status, wilaya: r.wilaya, city: r.city,
      createdAt: r.createdAt, mediaUrl: r.mediaUrl, mediaType: r.mediaType,
      latitude: exact ? r.latitude : (r.publicLatitude != null ? r.publicLatitude : Math.round(r.latitude * 100) / 100),
      longitude: exact ? r.longitude : (r.publicLongitude != null ? r.publicLongitude : Math.round(r.longitude * 100) / 100),
      approximate: !exact, mine: r.reporterId === req.user.id
    };
  }));
}));

// kept for backward compatibility with v1.x clients
router.get("/reports/search", auth, asyncHandler(async (req, res) => {
  const and = [await visibility(req.user), ...filters(req.query)];
  const rows = await prisma.report.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: 100, include: INCLUDE
  });
  res.json(await shapeReports(rows, req.user));
}));

router.get("/reports/:id", auth, asyncHandler(async (req, res) => {
  const r = await prisma.report.findUnique({ where: { id: req.params.id }, include: INCLUDE });
  if (!r) throw httpError(404, "NOT_FOUND", "Not found");
  const visible = isStaff(req.user) || r.reporterId === req.user.id || (await prisma.report.count({ where: { AND: [{ id: r.id }, await visibility(req.user)] } })) > 0;
  if (!visible) throw httpError(404, "NOT_FOUND", "Not found");
  res.json((await shapeReports([r], req.user))[0]);
}));

router.post("/reports", auth, reportLimiter, upload.array("media", 6), asyncHandler(async (req, res) => {
  const type = str(req.body.type, 40);
  const title = str(req.body.title, 160);
  const description = str(req.body.description, 5000);
  const wilaya = str(req.body.wilaya, 60);
  if (!type || !title || !description || !wilaya) throw httpError(400, "MISSING_FIELDS", "Missing report fields");
  const la = lat(req.body.latitude);
  const lo = lon(req.body.longitude);
  const s = await settings.all();
  const anonymous = bool(req.body.anonymous) && settings.isTrue(s.allowAnonymousReports);

  const files = req.files || [];
  const stored = [];
  for (const f of files) stored.push(await storeUpload(f, { kinds: ["image", "video", "file"], ownerId: req.user.id }));
  const first = stored[0] || null;

  const report = await prisma.report.create({
    data: {
      reporterId: req.user.id, type, title, description, wilaya, city: optStr(req.body.city, 80),
      latitude: la, longitude: lo, ...publicCoords(la, lo),
      mediaUrl: first ? first.url : null, mediaType: first ? first.mediaType : null,
      anonymous,
      evidence: { create: stored.slice(1).map((x) => ({ url: x.url, type: x.mediaType })) }
    },
    include: INCLUDE
  });
  notifyStaff("new_report", { title, wilaya }, { screen: "reports", reportId: report.id });
  res.status(201).json((await shapeReports([report], req.user))[0]);
}));

router.patch("/reports/:id/status", auth, staff, asyncHandler(async (req, res) => {
  const status = String(req.body.status || "");
  if (!STATUSES.includes(status)) throw httpError(400, "INVALID_STATUS", "Invalid report status");
  const note = optStr(req.body.note, 1000);
  const old = await prisma.report.findUnique({ where: { id: req.params.id }, select: { id: true, reporterId: true, title: true, status: true } });
  if (!old) throw httpError(404, "NOT_FOUND", "Not found");
  const r = await prisma.report.update({ where: { id: old.id }, data: { status, moderatorNote: note }, include: INCLUDE });
  await audit(req.user, "REPORT_STATUS", "REPORT", r.id, `${old.status} -> ${status}${note ? ` | ${note}` : ""}`);
  if (old.reporterId && old.reporterId !== req.user.id && old.status !== status) {
    notify(old.reporterId, "report_status", { title: old.title, status }, { data: { reportId: r.id } });
  }
  res.json((await shapeReports([r], req.user))[0]);
}));

router.post("/reports/:id/evidence", auth, upload.array("media", 6), asyncHandler(async (req, res) => {
  const r = await prisma.report.findUnique({ where: { id: req.params.id }, select: { id: true, reporterId: true } });
  if (!r) throw httpError(404, "NOT_FOUND", "Not found");
  if (r.reporterId !== req.user.id && !isStaff(req.user)) throw httpError(403, "FORBIDDEN", "Forbidden");
  const rows = [];
  for (const f of req.files || []) {
    const st = await storeUpload(f, { kinds: ["image", "video", "file"], ownerId: req.user.id });
    rows.push(await prisma.evidence.create({ data: { reportId: r.id, url: st.url, type: st.mediaType } }));
  }
  res.json(rows);
}));

router.delete("/reports/:id", auth, asyncHandler(async (req, res) => {
  const r = await prisma.report.findUnique({ where: { id: req.params.id }, select: { id: true, reporterId: true, status: true } });
  if (!r) throw httpError(404, "NOT_FOUND", "Not found");
  const owner = r.reporterId === req.user.id;
  if (!isStaff(req.user) && !(owner && r.status === "PENDING")) throw httpError(403, "FORBIDDEN", "Forbidden");
  await prisma.report.delete({ where: { id: r.id } });
  if (!owner) await audit(req.user, "REPORT_DELETE", "REPORT", r.id);
  res.json({ ok: true });
}));

module.exports = router;
module.exports.shapeReports = shapeReports;
module.exports.INCLUDE = INCLUDE;
module.exports.STATUSES = STATUSES;
