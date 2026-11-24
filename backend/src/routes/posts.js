const express = require("express");
const prisma = require("../lib/prisma");
const upload = require("../lib/upload");
const { auth, isStaff } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { USER_SELECT, toUsers } = require("../lib/users");
const { notify, notifyStaff } = require("../lib/notify");
const { audit } = require("../lib/audit");
const { asyncHandler, httpError, clampInt, str, optStr, lat, lon, parseDate, rateLimit } = require("../lib/util");

const router = express.Router();

const postLimiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 40, key: (req) => (req.user ? req.user.id : req.ip) });
const commentLimiter = rateLimit({ windowMs: 10 * 60 * 1000, max: 60, key: (req) => (req.user ? req.user.id : req.ip) });

const POST_INCLUDE = (me) => ({
  author: { select: USER_SELECT },
  _count: { select: { likes: true, comments: true } },
  likes: { where: { userId: me }, select: { userId: true } },
  saves: { where: { userId: me }, select: { userId: true } }
});

async function shapePosts(rows, me) {
  const authors = await toUsers(rows.map((p) => p.author));
  return rows.map((p, i) => ({
    id: p.id,
    title: p.title,
    body: p.body,
    wilaya: p.wilaya,
    city: p.city,
    latitude: p.latitude,
    longitude: p.longitude,
    mediaUrl: p.mediaUrl,
    mediaType: p.mediaType,
    hidden: p.hidden,
    createdAt: p.createdAt,
    author: authors[i],
    likesCount: p._count ? p._count.likes : 0,
    commentsCount: p._count ? p._count.comments : 0,
    likedByMe: !!(p.likes && p.likes.length),
    savedByMe: !!(p.saves && p.saves.length),
    mine: p.authorId === me
  }));
}

router.get("/feed", auth, asyncHandler(async (req, res) => {
  const scope = String(req.query.scope || "all");
  const before = parseDate(req.query.before);
  const where = { hidden: false };
  if (req.query.wilaya) where.wilaya = String(req.query.wilaya);
  if (before) where.createdAt = { lt: before };
  if (scope === "following") {
    const f = await prisma.follow.findMany({ where: { followerId: req.user.id }, select: { followingId: true } });
    where.authorId = { in: f.map((x) => x.followingId) };
  } else if (scope === "mine") {
    where.authorId = req.user.id;
    delete where.hidden;
  }
  const q = str(req.query.q, 80);
  if (q) where.OR = [{ title: { contains: q, mode: "insensitive" } }, { body: { contains: q, mode: "insensitive" } }];
  const rows = await prisma.post.findMany({
    where, orderBy: { createdAt: "desc" }, take: clampInt(req.query.limit, 20, 50),
    include: POST_INCLUDE(req.user.id)
  });
  res.json(await shapePosts(rows, req.user.id));
}));

router.get("/posts/:id", auth, asyncHandler(async (req, res) => {
  const p = await prisma.post.findUnique({ where: { id: req.params.id }, include: POST_INCLUDE(req.user.id) });
  if (!p || (p.hidden && p.authorId !== req.user.id && !isStaff(req.user))) throw httpError(404, "NOT_FOUND", "Post not found");
  res.json((await shapePosts([p], req.user.id))[0]);
}));

router.post("/posts", auth, postLimiter, upload.single("media"), asyncHandler(async (req, res) => {
  const body = str(req.body.body, 5000);
  const title = optStr(req.body.title, 160);
  if (!body && !req.file) throw httpError(400, "EMPTY_POST", "Post body cannot be empty");
  let media = null;
  if (req.file) media = await storeUpload(req.file, { kinds: ["image", "video"], ownerId: req.user.id });
  const post = await prisma.post.create({
    data: {
      authorId: req.user.id, title, body: body || null,
      wilaya: optStr(req.body.wilaya, 60), city: optStr(req.body.city, 80),
      latitude: lat(req.body.latitude), longitude: lon(req.body.longitude),
      mediaUrl: media ? media.url : null, mediaType: media ? media.mediaType : null
    },
    include: POST_INCLUDE(req.user.id)
  });
  res.status(201).json((await shapePosts([post], req.user.id))[0]);
}));

router.delete("/posts/:id", auth, asyncHandler(async (req, res) => {
  const p = await prisma.post.findUnique({ where: { id: req.params.id }, select: { id: true, authorId: true } });
  if (!p) throw httpError(404, "NOT_FOUND", "Post not found");
  if (p.authorId !== req.user.id && !isStaff(req.user)) throw httpError(403, "FORBIDDEN", "Forbidden");
  await prisma.post.delete({ where: { id: p.id } });
  if (p.authorId !== req.user.id) await audit(req.user, "POST_DELETE", "POST", p.id);
  res.json({ ok: true });
}));

router.post("/posts/:id/like", auth, asyncHandler(async (req, res) => {
  const post = await prisma.post.findUnique({ where: { id: req.params.id }, select: { id: true, authorId: true } });
  if (!post) throw httpError(404, "NOT_FOUND", "Post not found");
  const where = { userId_postId: { userId: req.user.id, postId: post.id } };
  const old = await prisma.like.findUnique({ where });
  if (old) await prisma.like.delete({ where });
  else {
    await prisma.like.create({ data: { userId: req.user.id, postId: post.id } });
    if (post.authorId !== req.user.id) {
      const [mu] = await toUsers([await prisma.user.findUnique({ where: { id: req.user.id }, select: USER_SELECT })]);
      notify(post.authorId, "like", { name: mu.name }, { data: { postId: post.id } });
    }
  }
  const likesCount = await prisma.like.count({ where: { postId: post.id } });
  res.json({ liked: !old, likesCount });
}));

router.post("/posts/:id/save", auth, asyncHandler(async (req, res) => {
  const post = await prisma.post.findUnique({ where: { id: req.params.id }, select: { id: true } });
  if (!post) throw httpError(404, "NOT_FOUND", "Post not found");
  const where = { userId_postId: { userId: req.user.id, postId: post.id } };
  const old = await prisma.save.findUnique({ where });
  if (old) await prisma.save.delete({ where });
  else await prisma.save.create({ data: { userId: req.user.id, postId: post.id } });
  res.json({ saved: !old });
}));

async function shapeComments(rows, me) {
  const users = await toUsers(rows.map((c) => c.user));
  return rows.map((c, i) => ({
    id: c.id, postId: c.postId, body: c.body, createdAt: c.createdAt, user: users[i], mine: c.userId === me
  }));
}

router.get("/posts/:id/comments", auth, asyncHandler(async (req, res) => {
  const rows = await prisma.comment.findMany({
    where: { postId: req.params.id }, orderBy: { createdAt: "asc" }, take: 300,
    include: { user: { select: USER_SELECT } }
  });
  res.json(await shapeComments(rows, req.user.id));
}));

router.post("/posts/:id/comments", auth, commentLimiter, asyncHandler(async (req, res) => {
  const body = str(req.body.body, 2000);
  if (!body) throw httpError(400, "EMPTY_COMMENT", "Comment cannot be empty");
  const post = await prisma.post.findUnique({ where: { id: req.params.id }, select: { id: true, authorId: true } });
  if (!post) throw httpError(404, "NOT_FOUND", "Post not found");
  const row = await prisma.comment.create({
    data: { postId: post.id, userId: req.user.id, body },
    include: { user: { select: USER_SELECT } }
  });
  const shaped = (await shapeComments([row], req.user.id))[0];
  if (post.authorId !== req.user.id) {
    notify(post.authorId, "comment", { name: shaped.user.name, text: body.slice(0, 80) }, { data: { postId: post.id } });
  }
  res.status(201).json(shaped);
}));

router.delete("/comments/:id", auth, asyncHandler(async (req, res) => {
  const c = await prisma.comment.findUnique({ where: { id: req.params.id }, include: { post: { select: { authorId: true } } } });
  if (!c) throw httpError(404, "NOT_FOUND", "Comment not found");
  if (c.userId !== req.user.id && c.post.authorId !== req.user.id && !isStaff(req.user)) throw httpError(403, "FORBIDDEN", "Forbidden");
  await prisma.comment.delete({ where: { id: c.id } });
  res.json({ ok: true });
}));

// Users can flag any content for the moderators.
const FLAG_TYPES = ["POST", "COMMENT", "USER", "REPORT", "MESSAGE", "CONVERSATION", "LOSTFOUND"];
router.post("/flags", auth, rateLimit({ windowMs: 60 * 60 * 1000, max: 30, key: (r) => r.ip }), asyncHandler(async (req, res) => {
  const targetType = String(req.body.targetType || "").toUpperCase();
  const targetId = str(req.body.targetId, 80);
  if (!FLAG_TYPES.includes(targetType) || !targetId) throw httpError(400, "MISSING_FIELDS", "Invalid flag");
  const dup = await prisma.flag.findFirst({ where: { reporterId: req.user.id, targetType, targetId, status: "OPEN" } });
  if (!dup) {
    await prisma.flag.create({ data: { reporterId: req.user.id, targetType, targetId, reason: optStr(req.body.reason, 1000) } });
    notifyStaff("new_flag", {}, { screen: "flags" });
  }
  res.json({ ok: true });
}));

module.exports = router;
module.exports.shapePosts = shapePosts;
module.exports.POST_INCLUDE = POST_INCLUDE;
