const express = require("express");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const prisma = require("../lib/prisma");
const settings = require("../lib/settings");
const { auth, staff, adminOnly, invalidate } = require("../lib/auth");
const { USER_SELECT, toUsers, toUser } = require("../lib/users");
const { notify, getIO, sendPush } = require("../lib/notify");
const { audit } = require("../lib/audit");
const { asyncHandler, httpError, clampInt, str, optStr, parseDate, bool, makeId } = require("../lib/util");
const { shapeReports, INCLUDE: REPORT_INCLUDE, STATUSES } = require("./reports");
const { shapePosts, POST_INCLUDE } = require("./posts");

const router = express.Router();
router.use("/admin", auth, staff);

// ---------------------------------------------------------------- dashboard
router.get("/admin/stats", asyncHandler(async (_req, res) => {
  const since = new Date(Date.now() - 7 * 24 * 3600 * 1000);
  const [users, posts, reports, pendingReports, verifiedUsers, lostFound, openFlags, pendingVerifications,
    newUsers7, newReports7, byStatus, byType, byWilaya, uRows, rRows, pRows] = await Promise.all([
    prisma.user.count(), prisma.post.count(), prisma.report.count(),
    prisma.report.count({ where: { status: "PENDING" } }),
    prisma.user.count({ where: { isVerified: true } }),
    prisma.lostFound.count(),
    prisma.flag.count({ where: { status: "OPEN" } }),
    prisma.verificationRequest.count({ where: { status: "PENDING" } }),
    prisma.user.count({ where: { createdAt: { gte: since } } }),
    prisma.report.count({ where: { createdAt: { gte: since } } }),
    prisma.report.groupBy({ by: ["status"], _count: { _all: true } }),
    prisma.report.groupBy({ by: ["type"], _count: { _all: true } }),
    prisma.report.groupBy({ by: ["wilaya"], _count: { _all: true }, orderBy: { _count: { wilaya: "desc" } }, take: 10 }),
    prisma.$queryRaw`SELECT to_char(date_trunc('day',"createdAt"),'YYYY-MM-DD') AS d, count(*)::int AS c FROM "User" WHERE "createdAt" > NOW() - INTERVAL '14 days' GROUP BY 1 ORDER BY 1`,
    prisma.$queryRaw`SELECT to_char(date_trunc('day',"createdAt"),'YYYY-MM-DD') AS d, count(*)::int AS c FROM "Report" WHERE "createdAt" > NOW() - INTERVAL '14 days' GROUP BY 1 ORDER BY 1`,
    prisma.$queryRaw`SELECT to_char(date_trunc('day',"createdAt"),'YYYY-MM-DD') AS d, count(*)::int AS c FROM "Post" WHERE "createdAt" > NOW() - INTERVAL '14 days' GROUP BY 1 ORDER BY 1`
  ]);
  // Fill missing days so charts are continuous.
  const days = [];
  for (let i = 13; i >= 0; i--) days.push(new Date(Date.now() - i * 24 * 3600 * 1000).toISOString().slice(0, 10));
  const fill = (rows) => { const m = new Map(rows.map((r) => [r.d, r.c])); return days.map((d) => ({ date: d, count: m.get(d) || 0 })); };
  res.json({
    users, posts, reports, pendingReports, verifiedUsers, lostFound, openFlags, pendingVerifications, newUsers7, newReports7,
    byStatus: Object.fromEntries(byStatus.map((x) => [x.status, x._count._all])),
    byType: Object.fromEntries(byType.map((x) => [x.type, x._count._all])),
    byWilaya: byWilaya.map((x) => ({ wilaya: x.wilaya, count: x._count._all })),
    series: { users: fill(uRows), reports: fill(rRows), posts: fill(pRows) }
  });
}));

// ---------------------------------------------------------------- reports
function reportWhere(q) {
  const and = [];
  if (q.status && STATUSES.includes(String(q.status))) and.push({ status: String(q.status) });
  if (q.type) and.push({ type: String(q.type) });
  if (q.wilaya) and.push({ wilaya: String(q.wilaya) });
  const text = str(q.q, 80);
  if (text) and.push({ OR: [{ title: { contains: text, mode: "insensitive" } }, { description: { contains: text, mode: "insensitive" } }] });
  const before = parseDate(q.before);
  if (before) and.push({ createdAt: { lt: before } });
  return { AND: and };
}

router.get("/admin/reports", asyncHandler(async (req, res) => {
  const rows = await prisma.report.findMany({
    where: reportWhere(req.query), orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 30, 200), include: REPORT_INCLUDE
  });
  res.json(await shapeReports(rows, req.user));
}));

router.get("/admin/reports/export.csv", asyncHandler(async (req, res) => {
  const rows = await prisma.report.findMany({ where: reportWhere(req.query), orderBy: { createdAt: "desc" }, take: 5000 });
  const esc = (v) => {
    let s = v === null || v === undefined ? "" : String(v);
    if (/^[=+\-@]/.test(s)) s = "'" + s; // neutralise spreadsheet formulas
    return `"${s.replace(/"/g, '""')}"`;
  };
  const head = ["id", "createdAt", "status", "type", "wilaya", "city", "title", "description", "latitude", "longitude", "anonymous", "moderatorNote"];
  const lines = [head.join(",")].concat(rows.map((r) => head.map((h) => esc(r[h] instanceof Date ? r[h].toISOString() : r[h])).join(",")));
  res.set({ "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="reports.csv"' });
  res.send("﻿" + lines.join("\n"));
}));

// ---------------------------------------------------------------- users
router.get("/admin/users", asyncHandler(async (req, res) => {
  const and = [];
  const q = str(req.query.q, 80);
  if (q) {
    const profs = await prisma.sawtAljazairProfile.findMany({ where: { displayName: { contains: q, mode: "insensitive" } }, select: { userId: true }, take: 50 });
    and.push({ OR: [
      { username: { contains: q, mode: "insensitive" } }, { email: { contains: q, mode: "insensitive" } },
      { displayName: { contains: q, mode: "insensitive" } }, { id: { in: profs.map((p) => p.userId) } }
    ] });
  }
  if (["USER", "MODERATOR", "ADMIN"].includes(String(req.query.role))) and.push({ role: String(req.query.role) });
  if (req.query.verified === "1") and.push({ isVerified: true });
  if (req.query.banned === "1") {
    const b = await prisma.sawtAljazairProfile.findMany({ where: { banned: true }, select: { userId: true } });
    and.push({ id: { in: b.map((x) => x.userId) } });
  }
  const before = parseDate(req.query.before);
  if (before) and.push({ createdAt: { lt: before } });
  const rows = await prisma.user.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 30, 100),
    select: { ...USER_SELECT, email: true }
  });
  res.json(await toUsers(rows, true));
}));

router.get("/admin/users/:id", asyncHandler(async (req, res) => {
  const u = await prisma.user.findUnique({ where: { id: req.params.id }, select: { ...USER_SELECT, email: true } });
  if (!u) throw httpError(404, "NOT_FOUND", "User not found");
  const [posts, reports, comments, followers, flags] = await Promise.all([
    prisma.post.count({ where: { authorId: u.id } }), prisma.report.count({ where: { reporterId: u.id } }),
    prisma.comment.count({ where: { userId: u.id } }), prisma.follow.count({ where: { followingId: u.id } }),
    prisma.flag.count({ where: { targetType: "USER", targetId: u.id } })
  ]);
  res.json({ user: await toUser(u, true), counts: { posts, reports, comments, followers, flags } });
}));

router.patch("/admin/users/:id", asyncHandler(async (req, res) => {
  const target = await prisma.user.findUnique({ where: { id: req.params.id }, select: { id: true, role: true, username: true } });
  if (!target) throw httpError(404, "NOT_FOUND", "User not found");
  const actorIsAdmin = req.user.role === "ADMIN";
  const targetIsStaff = ["ADMIN", "MODERATOR"].includes(target.role);
  if (target.id === req.user.id && (req.body.banned !== undefined || req.body.role !== undefined)) {
    throw httpError(400, "SELF_ACTION", "You cannot change your own role or ban yourself");
  }
  if (targetIsStaff && !actorIsAdmin) throw httpError(403, "FORBIDDEN", "Only administrators can modify staff");

  const userData = {};
  const profileData = {};
  const log = [];
  if (req.body.role !== undefined) {
    if (!actorIsAdmin) throw httpError(403, "FORBIDDEN", "Only administrators can change roles");
    if (!["USER", "MODERATOR", "ADMIN"].includes(req.body.role)) throw httpError(400, "INVALID_ROLE", "Invalid role");
    userData.role = req.body.role; log.push(`role=${req.body.role}`);
  }
  if (req.body.isVerified !== undefined) { userData.isVerified = bool(req.body.isVerified); log.push(`verified=${userData.isVerified}`); }
  if (req.body.banned !== undefined) {
    profileData.banned = bool(req.body.banned);
    profileData.bannedReason = profileData.banned ? optStr(req.body.bannedReason, 300) : null;
    log.push(`banned=${profileData.banned}`);
  }
  if (Object.keys(userData).length) await prisma.user.update({ where: { id: target.id }, data: userData });
  if (Object.keys(profileData).length) {
    await prisma.sawtAljazairProfile.upsert({ where: { userId: target.id }, create: { userId: target.id, ...profileData }, update: profileData });
  }
  invalidate(target.id);
  if (profileData.banned) {
    const io = getIO();
    if (io) io.in(`user:${target.id}`).disconnectSockets(true);
  }
  await audit(req.user, "USER_UPDATE", "USER", target.id, `${target.username}: ${log.join(", ")}`);
  const fresh = await prisma.user.findUnique({ where: { id: target.id }, select: { ...USER_SELECT, email: true } });
  res.json({ user: await toUser(fresh, true) });
}));

router.post("/admin/users/:id/reset-password", adminOnly, asyncHandler(async (req, res) => {
  const target = await prisma.user.findUnique({ where: { id: req.params.id }, select: { id: true, username: true } });
  if (!target) throw httpError(404, "NOT_FOUND", "User not found");
  const temp = crypto.randomBytes(6).toString("base64").replace(/[^A-Za-z0-9]/g, "x").slice(0, 10);
  await prisma.user.update({ where: { id: target.id }, data: { passwordHash: await bcrypt.hash(temp, 12) } });
  await audit(req.user, "USER_RESET_PASSWORD", "USER", target.id, target.username);
  res.json({ tempPassword: temp });
}));

router.delete("/admin/users/:id", adminOnly, asyncHandler(async (req, res) => {
  const target = await prisma.user.findUnique({ where: { id: req.params.id }, select: { id: true, username: true } });
  if (!target) throw httpError(404, "NOT_FOUND", "User not found");
  if (target.id === req.user.id) throw httpError(400, "SELF_ACTION", "You cannot delete yourself");
  await prisma.$transaction([
    prisma.sawtAljazairProfile.deleteMany({ where: { userId: target.id } }),
    prisma.user.delete({ where: { id: target.id } })
  ]);
  invalidate(target.id);
  await audit(req.user, "USER_DELETE", "USER", target.id, target.username);
  res.json({ ok: true });
}));

// ---------------------------------------------------------------- posts
router.get("/admin/posts", asyncHandler(async (req, res) => {
  const and = [];
  const q = str(req.query.q, 80);
  if (q) and.push({ OR: [{ title: { contains: q, mode: "insensitive" } }, { body: { contains: q, mode: "insensitive" } }] });
  if (req.query.hidden === "1") and.push({ hidden: true });
  const before = parseDate(req.query.before);
  if (before) and.push({ createdAt: { lt: before } });
  const rows = await prisma.post.findMany({
    where: { AND: and }, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 30, 100), include: POST_INCLUDE(req.user.id)
  });
  res.json(await shapePosts(rows, req.user.id));
}));

router.patch("/admin/posts/:id", asyncHandler(async (req, res) => {
  const hidden = bool(req.body.hidden);
  const p = await prisma.post.update({ where: { id: req.params.id }, data: { hidden } });
  await audit(req.user, hidden ? "POST_HIDE" : "POST_UNHIDE", "POST", p.id);
  res.json({ ok: true, hidden });
}));

router.get("/admin/lost-found", asyncHandler(async (req, res) => {
  const rows = await prisma.lostFound.findMany({ orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 50, 200), include: { user: { select: USER_SELECT } } });
  const users = await toUsers(rows.map((r) => r.user));
  res.json(rows.map((r, i) => ({ ...r, user: users[i] })));
}));

// ---------------------------------------------------------------- flags (content reports)
async function describeTarget(type, id) {
  try {
    if (type === "POST") { const p = await prisma.post.findUnique({ where: { id }, select: { title: true, body: true, hidden: true } }); return p ? { text: `${p.title || ""} ${p.body || ""}`.trim().slice(0, 200), hidden: p.hidden } : null; }
    if (type === "COMMENT") { const c = await prisma.comment.findUnique({ where: { id }, select: { body: true } }); return c ? { text: (c.body || "").slice(0, 200) } : null; }
    if (type === "REPORT") { const r = await prisma.report.findUnique({ where: { id }, select: { title: true, status: true } }); return r ? { text: r.title, status: r.status } : null; }
    if (type === "USER" || type === "CONVERSATION") { const u = await prisma.user.findUnique({ where: { id }, select: { username: true, displayName: true } }); return u ? { text: `${u.displayName} (@${u.username})` } : null; }
    if (type === "LOSTFOUND") { const l = await prisma.lostFound.findUnique({ where: { id }, select: { title: true } }); return l ? { text: l.title } : null; }
  } catch { /* ignore */ }
  return null;
}

router.get("/admin/flags", asyncHandler(async (req, res) => {
  const status = ["OPEN", "RESOLVED", "DISMISSED"].includes(String(req.query.status)) ? String(req.query.status) : "OPEN";
  const rows = await prisma.flag.findMany({ where: { status }, orderBy: { createdAt: "desc" }, take: 60 });
  const reporters = await prisma.user.findMany({ where: { id: { in: rows.map((r) => r.reporterId) } }, select: USER_SELECT });
  const rm = new Map((await toUsers(reporters)).map((u) => [u.id, u]));
  const out = [];
  for (const f of rows) out.push({ ...f, reporter: rm.get(f.reporterId) || null, target: await describeTarget(f.targetType, f.targetId) });
  res.json(out);
}));

router.patch("/admin/flags/:id", asyncHandler(async (req, res) => {
  const status = String(req.body.status || "");
  if (!["RESOLVED", "DISMISSED", "OPEN"].includes(status)) throw httpError(400, "INVALID_STATUS", "Invalid status");
  const f = await prisma.flag.findUnique({ where: { id: req.params.id } });
  if (!f) throw httpError(404, "NOT_FOUND", "Not found");
  const action = String(req.body.action || "");
  if (action === "DELETE_TARGET" || action === "HIDE_TARGET") {
    if (f.targetType === "POST") {
      if (action === "HIDE_TARGET") await prisma.post.updateMany({ where: { id: f.targetId }, data: { hidden: true } });
      else await prisma.post.deleteMany({ where: { id: f.targetId } });
    } else if (f.targetType === "COMMENT") await prisma.comment.deleteMany({ where: { id: f.targetId } });
    else if (f.targetType === "REPORT") await prisma.report.updateMany({ where: { id: f.targetId }, data: { status: "REJECTED" } });
    else if (f.targetType === "LOSTFOUND") await prisma.lostFound.deleteMany({ where: { id: f.targetId } });
  }
  const row = await prisma.flag.update({ where: { id: f.id }, data: { status, note: optStr(req.body.note, 500), handledBy: req.user.id } });
  await audit(req.user, "FLAG_HANDLE", f.targetType, f.targetId, `${status}${action ? ` / ${action}` : ""}`);
  res.json(row);
}));

// ---------------------------------------------------------------- verification
router.get("/admin/verification", asyncHandler(async (req, res) => {
  const status = ["PENDING", "APPROVED", "REJECTED"].includes(String(req.query.status)) ? String(req.query.status) : undefined;
  const rows = await prisma.verificationRequest.findMany({
    where: status ? { status } : {}, include: { user: { select: USER_SELECT } }, orderBy: { createdAt: "desc" }, take: 100
  });
  const users = await toUsers(rows.map((r) => r.user));
  res.json(rows.map((r, i) => ({ ...r, user: users[i] })));
}));

router.patch("/admin/verification/:id", asyncHandler(async (req, res) => {
  const status = String(req.body.status || "");
  if (!["APPROVED", "REJECTED", "PENDING"].includes(status)) throw httpError(400, "INVALID_STATUS", "Invalid status");
  const note = optStr(req.body.note, 500);
  const row = await prisma.verificationRequest.update({ where: { id: req.params.id }, data: { status, note } });
  if (status === "APPROVED") await prisma.user.update({ where: { id: row.userId }, data: { isVerified: true } });
  if (status === "REJECTED") await prisma.user.update({ where: { id: row.userId }, data: { isVerified: false } });
  invalidate(row.userId);
  if (status !== "PENDING") notify(row.userId, "verification", { approved: status === "APPROVED", note }, { data: { screen: "verification" } });
  await audit(req.user, "VERIFICATION", "USER", row.userId, status);
  res.json(row);
}));

// ---------------------------------------------------------------- broadcast notifications
router.post("/admin/broadcast", adminOnly, asyncHandler(async (req, res) => {
  const title = str(req.body.title, 120);
  const body = str(req.body.body, 500);
  const audience = String(req.body.audience || "ALL").toUpperCase();
  if (!title || !body) throw httpError(400, "MISSING_FIELDS", "Title and message are required");
  let wilaya = null;
  let ids = [];
  if (audience === "USER") {
    const uid = str(req.body.userId, 80);
    const u = uid ? await prisma.user.findFirst({ where: { OR: [{ id: uid }, { username: uid }] }, select: { id: true } }) : null;
    if (!u) throw httpError(404, "NOT_FOUND", "User not found");
    ids = [u.id];
  } else if (audience === "WILAYA") {
    wilaya = str(req.body.wilaya, 60);
    if (!wilaya) throw httpError(400, "MISSING_FIELDS", "Wilaya is required");
    ids = (await prisma.sawtAljazairProfile.findMany({ where: { wilaya, banned: false }, select: { userId: true } })).map((p) => p.userId);
  } else if (audience === "STAFF") {
    ids = (await prisma.user.findMany({ where: { role: { in: ["ADMIN", "MODERATOR"] } }, select: { id: true } })).map((u) => u.id);
  } else {
    const banned = new Set((await prisma.sawtAljazairProfile.findMany({ where: { banned: true }, select: { userId: true } })).map((p) => p.userId));
    ids = (await prisma.user.findMany({ select: { id: true } })).map((u) => u.id).filter((id) => !banned.has(id));
  }
  for (let i = 0; i < ids.length; i += 1000) {
    await prisma.notification.createMany({
      data: ids.slice(i, i + 1000).map((userId) => ({ userId, type: "broadcast", title, body, data: { screen: "notifications" } }))
    });
  }
  const io = getIO();
  if (io && ids.length) {
    const payload = { id: null, type: "broadcast", title, body, read: false, createdAt: new Date().toISOString() };
    for (let i = 0; i < ids.length; i += 500) io.to(ids.slice(i, i + 500).map((id) => `user:${id}`)).emit("notification:new", payload);
  }
  sendPush(ids, { title, body, data: { type: "broadcast" } });
  const rec = await prisma.broadcast.create({
    data: { id: makeId("b"), title, body, audience, wilaya, sentCount: ids.length, createdBy: req.user.id }
  });
  await audit(req.user, "BROADCAST", "BROADCAST", rec.id, `${audience}${wilaya ? `:${wilaya}` : ""} -> ${ids.length}`);
  res.json({ ok: true, sent: ids.length, id: rec.id });
}));

router.get("/admin/broadcasts", asyncHandler(async (_req, res) => {
  res.json(await prisma.broadcast.findMany({ orderBy: { createdAt: "desc" }, take: 50 }));
}));

// ---------------------------------------------------------------- settings & audit
router.get("/admin/settings", asyncHandler(async (_req, res) => { res.json(await settings.all()); }));

router.put("/admin/settings", adminOnly, asyncHandler(async (req, res) => {
  const changed = [];
  for (const key of Object.keys(settings.DEFAULTS)) {
    if (req.body[key] !== undefined) {
      const v = typeof req.body[key] === "boolean" ? String(req.body[key]) : String(req.body[key]).slice(0, 500);
      await settings.set(key, v);
      changed.push(key);
    }
  }
  await audit(req.user, "SETTINGS", "SETTINGS", null, changed.join(","));
  res.json(await settings.all());
}));

router.get("/admin/audit", asyncHandler(async (req, res) => {
  const before = parseDate(req.query.before);
  res.json(await prisma.auditLog.findMany({
    where: before ? { createdAt: { lt: before } } : {}, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 50, 200)
  }));
}));

module.exports = router;
