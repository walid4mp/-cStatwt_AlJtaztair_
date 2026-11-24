const express = require("express");
const bcrypt = require("bcryptjs");
const prisma = require("../lib/prisma");
const cfg = require("../lib/config");
const settings = require("../lib/settings");
const upload = require("../lib/upload");
const { auth, invalidate } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { toUser } = require("../lib/users");
const { asyncHandler, httpError, str, optStr, bool } = require("../lib/util");
const { shapePosts, POST_INCLUDE } = require("./posts");

const router = express.Router();

async function me(userId) {
  const u = await prisma.user.findUnique({ where: { id: userId } });
  if (!u) throw httpError(404, "NOT_FOUND", "User not found");
  const p = await prisma.sawtAljazairProfile.findUnique({ where: { userId } }).catch(() => null);
  return { ...(await toUser(u)), email: u.email, language: (p && p.language) || null };
}

router.get("/me", auth, asyncHandler(async (req, res) => {
  const [user, unreadNotifications, pub] = await Promise.all([
    me(req.user.id),
    prisma.notification.count({ where: { userId: req.user.id, read: false } }),
    settings.publicSettings()
  ]);
  prisma.sawtAljazairProfile.updateMany({ where: { userId: req.user.id }, data: { lastSeenAt: new Date() } }).catch(() => {});
  res.json({ user, unreadNotifications, settings: pub });
}));

router.patch("/me/profile", auth, upload.single("avatar"), asyncHandler(async (req, res) => {
  const b = req.body || {};
  const userData = {};
  const profileData = {};
  if (b.displayName !== undefined) {
    const name = str(b.displayName, 80);
    if (!name) throw httpError(400, "NAME_REQUIRED", "الاسم مطلوب");
    userData.displayName = name;
    profileData.displayName = name;
  }
  if (b.bio !== undefined) {
    const bio = str(b.bio, 500);
    userData.bio = bio || null;
  }
  if (b.phone !== undefined) userData.phone = optStr(b.phone, 30);
  if (b.whatsapp !== undefined) userData.whatsapp = optStr(b.whatsapp, 30);
  if (b.wilaya !== undefined) profileData.wilaya = optStr(b.wilaya, 60);
  if (b.language !== undefined && cfg.languages.includes(b.language)) profileData.language = b.language;
  if (bool(b.removeAvatar)) userData.avatarUrl = null;
  if (req.file) {
    const stored = await storeUpload(req.file, { kinds: ["image"], ownerId: req.user.id });
    userData.avatarUrl = stored.url;
  }
  await prisma.$transaction(async (tx) => {
    if (Object.keys(userData).length) await tx.user.update({ where: { id: req.user.id }, data: userData });
    await tx.sawtAljazairProfile.upsert({
      where: { userId: req.user.id },
      create: { userId: req.user.id, ...profileData },
      update: profileData
    });
  });
  res.json({ user: await me(req.user.id) });
}));

router.put("/me/language", auth, asyncHandler(async (req, res) => {
  const language = cfg.languages.includes(req.body.language) ? req.body.language : null;
  if (!language) throw httpError(400, "INVALID_LANGUAGE", "Unsupported language");
  await prisma.sawtAljazairProfile.upsert({
    where: { userId: req.user.id }, create: { userId: req.user.id, language }, update: { language }
  });
  res.json({ ok: true, language });
}));

router.post("/me/password", auth, asyncHandler(async (req, res) => {
  const current = String(req.body.current || "");
  const next = String(req.body.next || "");
  if (next.length < 6 || next.length > 128) throw httpError(400, "WEAK_PASSWORD", "Password must be at least 6 characters");
  const u = await prisma.user.findUnique({ where: { id: req.user.id } });
  if (!u || !(await bcrypt.compare(current, u.passwordHash))) throw httpError(403, "INVALID_CREDENTIALS", "Current password is incorrect");
  await prisma.user.update({ where: { id: u.id }, data: { passwordHash: await bcrypt.hash(next, 12) } });
  res.json({ ok: true });
}));

router.delete("/me", auth, asyncHandler(async (req, res) => {
  const password = String(req.body.password || "");
  const u = await prisma.user.findUnique({ where: { id: req.user.id } });
  if (!u || !(await bcrypt.compare(password, u.passwordHash))) throw httpError(403, "INVALID_CREDENTIALS", "Password is incorrect");
  if (u.role === "ADMIN") {
    const admins = await prisma.user.count({ where: { role: "ADMIN" } });
    if (admins <= 1) throw httpError(400, "LAST_ADMIN", "The last administrator cannot delete the account");
  }
  await prisma.$transaction([
    prisma.sawtAljazairProfile.deleteMany({ where: { userId: u.id } }),
    prisma.user.delete({ where: { id: u.id } })
  ]);
  invalidate(u.id);
  res.json({ ok: true });
}));

router.post("/me/devices", auth, asyncHandler(async (req, res) => {
  const token = str(req.body.token, 400);
  if (!token) throw httpError(400, "MISSING_FIELDS", "token required");
  await prisma.deviceToken.upsert({
    where: { token },
    create: { token, userId: req.user.id, platform: optStr(req.body.platform, 20) },
    update: { userId: req.user.id, platform: optStr(req.body.platform, 20) }
  });
  res.json({ ok: true });
}));

router.delete("/me/devices", auth, asyncHandler(async (req, res) => {
  const token = str(req.body.token, 400);
  if (token) await prisma.deviceToken.deleteMany({ where: { token, userId: req.user.id } });
  res.json({ ok: true });
}));

router.get("/me/saved", auth, asyncHandler(async (req, res) => {
  const rows = await prisma.post.findMany({
    where: { hidden: false, saves: { some: { userId: req.user.id } } },
    orderBy: { createdAt: "desc" }, take: 50,
    include: POST_INCLUDE(req.user.id)
  });
  res.json(await shapePosts(rows, req.user.id));
}));

router.get("/badges", auth, asyncHandler(async (req, res) => {
  const [notifications, messages] = await Promise.all([
    prisma.notification.count({ where: { userId: req.user.id, read: false } }),
    prisma.message.count({
      where: { senderId: { not: req.user.id }, readAt: null, conversation: { members: { some: { userId: req.user.id } } } }
    })
  ]);
  res.json({ notifications, messages });
}));

module.exports = router;
