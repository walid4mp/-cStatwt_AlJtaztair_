const express = require("express");
const prisma = require("../lib/prisma");
const upload = require("../lib/upload");
const { auth } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { USER_SELECT, toUsers } = require("../lib/users");
const { getIO, sendPush, emitUser, notifyStaff } = require("../lib/notify");
const { asyncHandler, httpError, clampInt, str, optStr, parseDate, rateLimit } = require("../lib/util");

const router = express.Router();
const messageLimiter = rateLimit({ windowMs: 60 * 1000, max: 60, key: (req) => (req.user ? req.user.id : req.ip) });

function shapeMessage(m) {
  return {
    id: m.id, conversationId: m.conversationId, senderId: m.senderId, body: m.body || "",
    mediaUrl: m.mediaUrl, mediaType: m.mediaType, createdAt: m.createdAt, readAt: m.readAt
  };
}

async function membership(conversationId, userId) {
  const members = await prisma.conversationMember.findMany({ where: { conversationId } });
  const mine = members.find((m) => m.userId === userId);
  if (!mine) throw httpError(403, "FORBIDDEN", "Forbidden");
  const other = members.find((m) => m.userId !== userId) || null;
  return { members, mine, other };
}

async function blockState(conversationId, me, otherId) {
  if (!otherId) return { byMe: false, byOther: false };
  const rows = await prisma.block.findMany({ where: { conversationId } });
  return {
    byMe: rows.some((b) => b.blockerId === me && b.blockedId === otherId),
    byOther: rows.some((b) => b.blockerId === otherId && b.blockedId === me)
  };
}

async function shapeConversations(rows, me) {
  const withMsgs = rows.filter((c) => c.messages.length > 0);
  const ids = withMsgs.map((c) => c.id);
  const unread = ids.length
    ? await prisma.message.groupBy({ by: ["conversationId"], where: { conversationId: { in: ids }, senderId: { not: me }, readAt: null }, _count: { _all: true } })
    : [];
  const unreadMap = new Map(unread.map((u) => [u.conversationId, u._count._all]));
  const otherIds = rows.map((c) => (c.members.find((m) => m.userId !== me) || {}).userId).filter(Boolean);
  const users = await prisma.user.findMany({ where: { id: { in: otherIds } }, select: USER_SELECT });
  const shaped = await toUsers(users);
  const userMap = new Map(shaped.map((u) => [u.id, u]));
  return rows.map((c) => {
    const mine = c.members.find((m) => m.userId === me);
    const other = c.members.find((m) => m.userId !== me);
    const last = c.messages[0] || null;
    return {
      id: c.id,
      other: other ? userMap.get(other.userId) || null : null,
      lastMessage: last ? shapeMessage(last) : null,
      unread: unreadMap.get(c.id) || 0,
      muted: !!(mine && mine.muted),
      blockedByMe: c.blocks.some((b) => b.blockerId === me),
      blockedMe: c.blocks.some((b) => b.blockedId === me),
      updatedAt: last ? last.createdAt : c.createdAt
    };
  });
}

const CONV_INCLUDE = { members: true, blocks: true, messages: { orderBy: { createdAt: "desc" }, take: 1 } };

router.get("/conversations", auth, asyncHandler(async (req, res) => {
  const rows = await prisma.conversation.findMany({ where: { members: { some: { userId: req.user.id } } }, include: CONV_INCLUDE });
  const out = (await shapeConversations(rows, req.user.id)).filter((c) => c.lastMessage);
  out.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  res.json(out);
}));

router.get("/conversations/:id", auth, asyncHandler(async (req, res) => {
  await membership(req.params.id, req.user.id);
  const row = await prisma.conversation.findUnique({ where: { id: req.params.id }, include: CONV_INCLUDE });
  res.json((await shapeConversations([row], req.user.id))[0]);
}));

router.post("/conversations", auth, asyncHandler(async (req, res) => {
  const otherId = str(req.body.userId, 80);
  if (!otherId || otherId === req.user.id) throw httpError(400, "INVALID_USER", "Invalid user");
  const other = await prisma.user.findUnique({ where: { id: otherId }, select: USER_SELECT });
  if (!other) throw httpError(404, "NOT_FOUND", "User not found");
  let conv = await prisma.conversation.findFirst({
    where: { AND: [{ members: { some: { userId: req.user.id } } }, { members: { some: { userId: otherId } } }] },
    include: { members: true }
  });
  if (!conv || conv.members.length !== 2) {
    conv = await prisma.conversation.create({
      data: { members: { create: [{ userId: req.user.id }, { userId: otherId }] } },
      include: { members: true }
    });
  }
  const [ou] = await toUsers([other]);
  const bs = await blockState(conv.id, req.user.id, otherId);
  res.json({ id: conv.id, other: ou, blockedByMe: bs.byMe, blockedMe: bs.byOther });
}));

router.get("/conversations/:id/messages", auth, asyncHandler(async (req, res) => {
  const { other } = await membership(req.params.id, req.user.id);
  const before = parseDate(req.query.before);
  const rows = await prisma.message.findMany({
    where: { conversationId: req.params.id, ...(before ? { createdAt: { lt: before } } : {}) },
    orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 40, 100)
  });
  const bs = await blockState(req.params.id, req.user.id, other && other.userId);
  res.set("X-Blocked-By-Me", String(bs.byMe)).set("X-Blocked-Me", String(bs.byOther));
  res.json(rows.reverse().map(shapeMessage));
}));

async function userInRoom(room, userId) {
  const io = getIO();
  if (!io) return false;
  try {
    const sockets = await io.in(room).fetchSockets();
    return sockets.some((s) => s.user && s.user.id === userId);
  } catch { return false; }
}

router.post("/conversations/:id/messages", auth, messageLimiter, upload.single("media"), asyncHandler(async (req, res) => {
  const { other, members } = await membership(req.params.id, req.user.id);
  if (!other || members.length !== 2) throw httpError(400, "INVALID_CONVERSATION", "Invalid conversation");
  const bs = await blockState(req.params.id, req.user.id, other.userId);
  if (bs.byMe || bs.byOther) throw httpError(403, "BLOCKED", "Conversation is blocked");
  const body = str(req.body.body, 5000);
  if (!body && !req.file) throw httpError(400, "EMPTY_MESSAGE", "Message cannot be empty");
  let media = null;
  if (req.file) media = await storeUpload(req.file, { kinds: ["image", "video"], ownerId: req.user.id });
  const msg = await prisma.message.create({
    data: {
      conversationId: req.params.id, senderId: req.user.id, body: body || null,
      mediaUrl: media ? media.url : null, mediaType: media ? media.mediaType : null
    }
  });
  const shaped = shapeMessage(msg);
  const meRow = await prisma.user.findUnique({ where: { id: req.user.id }, select: USER_SELECT });
  const [mu] = await toUsers([meRow]);
  const io = getIO();
  const room = `conversation:${req.params.id}`;
  if (io) {
    const live = { ...shaped, senderName: mu.name, senderAvatar: mu.avatarUrl };
    io.to(room).emit("message:new", live);
    emitUser(other.userId, "message:new", live); // lets the recipient's inbox/badge update
  }
  // Background push (only when FCM is configured), unless the recipient is muted or already in the chat.
  if (!other.muted && !(await userInRoom(room, other.userId))) {
    const preview = body ? body.slice(0, 120) : (media && media.mediaType === "VIDEO" ? "🎬" : "📷");
    sendPush([other.userId], { title: mu.name, body: preview, data: { type: "message", conversationId: req.params.id } });
  }
  res.status(201).json(shaped);
}));

router.delete("/messages/:id", auth, asyncHandler(async (req, res) => {
  const m = await prisma.message.findUnique({ where: { id: req.params.id } });
  if (!m) throw httpError(404, "NOT_FOUND", "Not found");
  if (m.senderId !== req.user.id) throw httpError(403, "FORBIDDEN", "Forbidden");
  await prisma.message.delete({ where: { id: m.id } });
  const io = getIO();
  if (io && m.conversationId) io.to(`conversation:${m.conversationId}`).emit("message:deleted", { id: m.id, conversationId: m.conversationId });
  res.json({ ok: true });
}));

router.patch("/conversations/:id/read", auth, asyncHandler(async (req, res) => {
  await membership(req.params.id, req.user.id);
  const now = new Date();
  await prisma.conversationMember.updateMany({ where: { conversationId: req.params.id, userId: req.user.id }, data: { lastReadAt: now } });
  await prisma.message.updateMany({
    where: { conversationId: req.params.id, senderId: { not: req.user.id }, readAt: null }, data: { readAt: now }
  });
  const io = getIO();
  if (io) io.to(`conversation:${req.params.id}`).emit("messages:read", { conversationId: req.params.id, by: req.user.id, at: now });
  res.json({ ok: true });
}));

router.patch("/conversations/:id/mute", auth, asyncHandler(async (req, res) => {
  await membership(req.params.id, req.user.id);
  const muted = req.body.muted === true || req.body.muted === "true";
  await prisma.conversationMember.updateMany({ where: { conversationId: req.params.id, userId: req.user.id }, data: { muted } });
  res.json({ ok: true, muted });
}));

router.post("/conversations/:id/block", auth, asyncHandler(async (req, res) => {
  const { other } = await membership(req.params.id, req.user.id);
  if (other) {
    await prisma.block.upsert({
      where: { conversationId_blockerId_blockedId: { conversationId: req.params.id, blockerId: req.user.id, blockedId: other.userId } },
      create: { conversationId: req.params.id, blockerId: req.user.id, blockedId: other.userId },
      update: {}
    });
  }
  res.json({ ok: true, blocked: true });
}));

router.delete("/conversations/:id/block", auth, asyncHandler(async (req, res) => {
  await membership(req.params.id, req.user.id);
  await prisma.block.deleteMany({ where: { conversationId: req.params.id, blockerId: req.user.id } });
  res.json({ ok: true, blocked: false });
}));

router.post("/conversations/:id/report", auth, asyncHandler(async (req, res) => {
  const { other } = await membership(req.params.id, req.user.id);
  const last = await prisma.message.findMany({ where: { conversationId: req.params.id }, orderBy: { createdAt: "desc" }, take: 10 });
  const snippet = last.reverse().map((m) => `${m.senderId === req.user.id ? "reporter" : "other"}: ${m.body || "[media]"}`).join("\n");
  const reason = `${optStr(req.body.reason, 500) || ""}\n--- last messages ---\n${snippet}`.slice(0, 2500);
  await prisma.flag.create({ data: { reporterId: req.user.id, targetType: "CONVERSATION", targetId: other ? other.userId : req.params.id, reason } });
  notifyStaff("new_flag", {}, { screen: "flags" });
  res.json({ ok: true });
}));

module.exports = router;
