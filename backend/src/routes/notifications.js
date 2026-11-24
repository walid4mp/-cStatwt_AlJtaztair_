const express = require("express");
const prisma = require("../lib/prisma");
const { auth } = require("../lib/auth");
const { asyncHandler, clampInt, parseDate } = require("../lib/util");

const router = express.Router();

router.get("/notifications", auth, asyncHandler(async (req, res) => {
  const before = parseDate(req.query.before);
  const rows = await prisma.notification.findMany({
    where: { userId: req.user.id, ...(before ? { createdAt: { lt: before } } : {}) },
    orderBy: { createdAt: "desc" },
    take: clampInt(req.query.limit, 30, 100)
  });
  res.json(rows.map((n) => ({ ...n, title: n.title || "", body: n.body || "" })));
}));

router.post("/notifications/read", auth, asyncHandler(async (req, res) => {
  const ids = Array.isArray(req.body.ids) ? req.body.ids.map(String).slice(0, 200) : null;
  await prisma.notification.updateMany({
    where: { userId: req.user.id, read: false, ...(ids ? { id: { in: ids } } : {}) },
    data: { read: true }
  });
  res.json({ ok: true });
}));

router.delete("/notifications/:id", auth, asyncHandler(async (req, res) => {
  await prisma.notification.deleteMany({ where: { id: req.params.id, userId: req.user.id } });
  res.json({ ok: true });
}));

router.delete("/notifications", auth, asyncHandler(async (req, res) => {
  await prisma.notification.deleteMany({ where: { userId: req.user.id } });
  res.json({ ok: true });
}));

module.exports = router;
