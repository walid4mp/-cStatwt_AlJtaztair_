const jwt = require("jsonwebtoken");
const prisma = require("./prisma");
const { JWT_SECRET } = require("./config");

function sign(user) {
  return jwt.sign({ id: user.id, role: user.role, username: user.username }, JWT_SECRET, { expiresIn: "30d" });
}

const cache = new Map(); // id -> { at, value }
const TTL = 20000;

function invalidate(id) { cache.delete(id); }

async function loadAuthUser(id) {
  const hit = cache.get(id);
  if (hit && Date.now() - hit.at < TTL) return hit.value;
  const user = await prisma.user.findUnique({ where: { id }, select: { id: true, role: true, username: true, isVerified: true } });
  let value = null;
  if (user) {
    let banned = false, bannedReason = null;
    try {
      const p = await prisma.sawtAljazairProfile.findUnique({ where: { userId: id }, select: { banned: true, bannedReason: true } });
      banned = !!(p && p.banned);
      bannedReason = (p && p.bannedReason) || null;
    } catch { /* profile table optional */ }
    value = { ...user, banned, bannedReason };
  }
  cache.set(id, { at: Date.now(), value });
  return value;
}

function tokenFrom(req) {
  const raw = req.headers.authorization || "";
  return raw.startsWith("Bearer ") ? raw.slice(7) : null;
}

async function auth(req, res, next) {
  try {
    const token = tokenFrom(req);
    if (!token) return res.status(401).json({ code: "UNAUTHORIZED", error: "Unauthorized" });
    let payload;
    try { payload = jwt.verify(token, JWT_SECRET); }
    catch { return res.status(401).json({ code: "INVALID_TOKEN", error: "Invalid token" }); }
    const u = await loadAuthUser(payload.id);
    if (!u) return res.status(401).json({ code: "INVALID_TOKEN", error: "Account not found" });
    if (u.banned) return res.status(403).json({ code: "BANNED", error: u.bannedReason || "Account restricted" });
    req.user = { id: u.id, role: u.role, username: u.username, isVerified: u.isVerified };
    next();
  } catch (e) { next(e); }
}

function isStaff(user) { return !!user && ["ADMIN", "MODERATOR"].includes(user.role); }

function staff(req, res, next) {
  if (!isStaff(req.user)) return res.status(403).json({ code: "FORBIDDEN", error: "Admin only" });
  next();
}

function adminOnly(req, res, next) {
  if (!req.user || req.user.role !== "ADMIN") return res.status(403).json({ code: "FORBIDDEN", error: "Administrator only" });
  next();
}

function verifySocketToken(token) {
  return jwt.verify(token, JWT_SECRET);
}

module.exports = { sign, auth, staff, adminOnly, isStaff, invalidate, loadAuthUser, verifySocketToken };
