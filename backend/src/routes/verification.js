const express = require("express");
const prisma = require("../lib/prisma");
const upload = require("../lib/upload");
const { auth } = require("../lib/auth");
const { storeUpload } = require("../lib/storage");
const { USER_SELECT, toUsers } = require("../lib/users");
const { notifyStaff } = require("../lib/notify");
const { asyncHandler, str } = require("../lib/util");

const router = express.Router();

router.post("/verification/request", auth, upload.single("document"), asyncHandler(async (req, res) => {
  let documentUrl = null;
  if (req.file) documentUrl = (await storeUpload(req.file, { kinds: ["image", "file"], ownerId: req.user.id })).url;
  const reason = str(req.body.reason, 1000);
  const existing = await prisma.verificationRequest.findUnique({ where: { userId: req.user.id } });
  const row = await prisma.verificationRequest.upsert({
    where: { userId: req.user.id },
    update: { reason, documentUrl: documentUrl || (existing && existing.documentUrl) || null, status: "PENDING", note: null },
    create: { userId: req.user.id, reason, documentUrl }
  });
  const me = await prisma.user.findUnique({ where: { id: req.user.id }, select: USER_SELECT });
  const [mu] = await toUsers([me]);
  notifyStaff("new_verification", { name: mu.name }, { screen: "verification" });
  res.json(row);
}));

router.get("/verification/me", auth, asyncHandler(async (req, res) => {
  res.json(await prisma.verificationRequest.findUnique({ where: { userId: req.user.id } }));
}));

module.exports = router;
