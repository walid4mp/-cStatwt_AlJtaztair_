const express = require("express");
const prisma = require("../lib/prisma");
const { auth, isStaff } = require("../lib/auth");
const { USER_SELECT, toUsers, toUser } = require("../lib/users");
const { notify } = require("../lib/notify");
const { asyncHandler, httpError, str } = require("../lib/util");
const { shapePosts, POST_INCLUDE } = require("./posts");

const router = express.Router();

router.get("/users/search", auth, asyncHandler(async (req, res) => {
  const q = str(req.query.q, 60);
  if (!q) return res.json([]);
  const profiles = await prisma.sawtAljazairProfile.findMany({
    where: { displayName: { contains: q, mode: "insensitive" } }, select: { userId: true }, take: 30
  });
  const rows = await prisma.user.findMany({
    where: {
      OR: [
        { username: { contains: q, mode: "insensitive" } },
        { displayName: { contains: q, mode: "insensitive" } },
        { id: { in: profiles.map((p) => p.userId) } }
      ]
    },
    select: USER_SELECT, take: 30
  });
  res.json(await toUsers(rows));
}));

router.get("/users/:id", auth, asyncHandler(async (req, res) => {
  const u = await prisma.user.findUnique({ where: { id: req.params.id }, select: USER_SELECT });
  if (!u) throw httpError(404, "NOT_FOUND", "User not found");
  const [posts, followers, following, rel] = await Promise.all([
    prisma.post.count({ where: { authorId: u.id, hidden: false } }),
    prisma.follow.count({ where: { followingId: u.id } }),
    prisma.follow.count({ where: { followerId: u.id } }),
    prisma.follow.findUnique({ where: { followerId_followingId: { followerId: req.user.id, followingId: u.id } } })
  ]);
  res.json({
    user: await toUser(u, isStaff(req.user)),
    stats: { posts, followers, following },
    isFollowing: !!rel,
    isMe: u.id === req.user.id
  });
}));

router.get("/users/:id/posts", auth, asyncHandler(async (req, res) => {
  const rows = await prisma.post.findMany({
    where: { authorId: req.params.id, ...(req.params.id === req.user.id || isStaff(req.user) ? {} : { hidden: false }) },
    orderBy: { createdAt: "desc" }, take: 50,
    include: POST_INCLUDE(req.user.id)
  });
  res.json(await shapePosts(rows, req.user.id));
}));

router.post("/follow/:id", auth, asyncHandler(async (req, res) => {
  const followingId = req.params.id;
  if (followingId === req.user.id) throw httpError(400, "INVALID_USER", "Cannot follow yourself");
  const target = await prisma.user.findUnique({ where: { id: followingId }, select: { id: true } });
  if (!target) throw httpError(404, "NOT_FOUND", "User not found");
  const where = { followerId_followingId: { followerId: req.user.id, followingId } };
  const old = await prisma.follow.findUnique({ where });
  if (old) await prisma.follow.delete({ where });
  else {
    await prisma.follow.create({ data: { followerId: req.user.id, followingId } });
    const me = await prisma.user.findUnique({ where: { id: req.user.id }, select: USER_SELECT });
    const [mu] = await toUsers([me]);
    notify(followingId, "follow", { name: mu.name }, { data: { userId: req.user.id } });
  }
  const followers = await prisma.follow.count({ where: { followingId } });
  res.json({ following: !old, followers });
}));

module.exports = router;
