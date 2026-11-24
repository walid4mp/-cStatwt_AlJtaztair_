const express = require("express");
const bcrypt = require("bcryptjs");
const prisma = require("../lib/prisma");
const cfg = require("../lib/config");
const settings = require("../lib/settings");
const { sign } = require("../lib/auth");
const { toUser } = require("../lib/users");
const { notify } = require("../lib/notify");
const { sendMail } = require("../lib/mailer");
const { asyncHandler, httpError, str, optStr, rateLimit, randomCode, sha } = require("../lib/util");

const router = express.Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 20,
  key: (req) => `${req.ip}|${String((req.body && req.body.email) || "").toLowerCase()}`
});
const registerLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 20 });
const forgotLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 8 });

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function promoteIfAdmin(user) {
  if (user && cfg.adminEmails.includes(String(user.email || "").toLowerCase()) && user.role !== "ADMIN") {
    return prisma.user.update({ where: { id: user.id }, data: { role: "ADMIN" } });
  }
  return user;
}

async function touchProfile(userId, data) {
  await prisma.sawtAljazairProfile.upsert({
    where: { userId },
    create: { userId, ...data },
    update: data
  });
}

router.post("/auth/register", registerLimiter, asyncHandler(async (req, res) => {
  const s = await settings.all();
  if (!settings.isTrue(s.registrationOpen)) throw httpError(403, "REGISTRATION_CLOSED", "التسجيل مغلق مؤقتًا");
  const username = str(req.body.username, 40);
  const displayName = str(req.body.name, 80) || username;
  const email = str(req.body.email, 160).toLowerCase();
  const password = String(req.body.password || "");
  const wilaya = optStr(req.body.wilaya, 60);
  const language = cfg.languages.includes(req.body.language) ? req.body.language : "ar";
  if (!username || !email || !password) throw httpError(400, "MISSING_FIELDS", "Missing fields");
  if (username.length < 3 || username.length > 30) throw httpError(400, "INVALID_USERNAME", "Invalid username");
  if (!/^[A-Za-z0-9_.-]+$/.test(username)) throw httpError(400, "INVALID_USERNAME_CHARS", "Username contains invalid characters");
  if (!EMAIL_RE.test(email)) throw httpError(400, "INVALID_EMAIL", "Invalid email");
  if (password.length < 6 || password.length > 128) throw httpError(400, "WEAK_PASSWORD", "Password must be at least 6 characters");

  const exists = await prisma.user.findFirst({
    where: { OR: [{ email }, { username: { equals: username, mode: "insensitive" } }] },
    select: { id: true }
  });
  if (exists) throw httpError(409, "ALREADY_EXISTS", "Username or email already exists");

  const passwordHash = await bcrypt.hash(password, 12);
  let user;
  try {
    user = await prisma.user.create({ data: { username, displayName, email, passwordHash } });
    await touchProfile(user.id, { displayName, wilaya, language });
  } catch (e) {
    if (e && (e.code === "P2002" || e.code === "23505")) throw httpError(409, "ALREADY_EXISTS", "Username or email already exists");
    throw e;
  }
  user = await promoteIfAdmin(user);
  notify(user.id, "welcome", { name: displayName }, { push: false });
  res.status(201).json({ token: sign(user), user: { ...(await toUser(user)), email: user.email, language } });
}));

router.post("/auth/login", loginLimiter, asyncHandler(async (req, res) => {
  const identifier = str(req.body.email || req.body.identifier, 160).toLowerCase();
  const password = String(req.body.password || "");
  if (!identifier || !password) throw httpError(400, "MISSING_FIELDS", "Missing fields");
  let user = await prisma.user.findFirst({
    where: identifier.includes("@") ? { email: identifier } : { username: { equals: identifier, mode: "insensitive" } }
  });
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) throw httpError(401, "INVALID_CREDENTIALS", "Invalid credentials");
  const p = await prisma.sawtAljazairProfile.findUnique({ where: { userId: user.id } }).catch(() => null);
  if (p && p.banned) throw httpError(403, "BANNED", p.bannedReason || "Account restricted");
  user = await promoteIfAdmin(user);
  prisma.sawtAljazairProfile.updateMany({ where: { userId: user.id }, data: { lastSeenAt: new Date() } }).catch(() => {});
  res.json({ token: sign(user), user: { ...(await toUser(user)), email: user.email, language: (p && p.language) || null } });
}));

// ---- password reset by emailed 6-digit code ----
router.post("/auth/forgot", forgotLimiter, asyncHandler(async (req, res) => {
  const email = str(req.body.email, 160).toLowerCase();
  const mailReady = !!cfg.smtp.host;
  if (EMAIL_RE.test(email)) {
    const user = await prisma.user.findUnique({ where: { email }, select: { id: true } });
    if (user) {
      const code = randomCode(6);
      await prisma.passwordReset.deleteMany({ where: { userId: user.id } });
      await prisma.passwordReset.create({
        data: { userId: user.id, codeHash: sha(code + user.id), expiresAt: new Date(Date.now() + 15 * 60 * 1000) }
      });
      sendMail(email, "Sawt Aljazair — password reset / استعادة كلمة المرور", `Your code / رمزك: ${code}\n(15 min / 15 دقيقة)`)
        .catch((e) => console.error("mail failed", e.message));
    }
  }
  // Always the same answer so the endpoint can't be used to discover accounts.
  res.json({ ok: true, emailConfigured: mailReady });
}));

router.post("/auth/reset", forgotLimiter, asyncHandler(async (req, res) => {
  const email = str(req.body.email, 160).toLowerCase();
  const code = str(req.body.code, 12);
  const password = String(req.body.password || "");
  if (password.length < 6 || password.length > 128) throw httpError(400, "WEAK_PASSWORD", "Password must be at least 6 characters");
  const user = await prisma.user.findUnique({ where: { email }, select: { id: true } });
  const reset = user ? await prisma.passwordReset.findFirst({ where: { userId: user.id }, orderBy: { createdAt: "desc" } }) : null;
  if (!user || !reset || reset.expiresAt < new Date() || reset.attempts >= 5) throw httpError(400, "INVALID_CODE", "Invalid or expired code");
  if (reset.codeHash !== sha(code + user.id)) {
    await prisma.passwordReset.update({ where: { id: reset.id }, data: { attempts: { increment: 1 } } });
    throw httpError(400, "INVALID_CODE", "Invalid or expired code");
  }
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await bcrypt.hash(password, 12) } });
  await prisma.passwordReset.deleteMany({ where: { userId: user.id } });
  res.json({ ok: true });
}));

router.get("/settings/public", asyncHandler(async (_req, res) => {
  res.json(await settings.publicSettings());
}));

module.exports = router;
