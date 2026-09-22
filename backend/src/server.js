const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { Server } = require("socket.io");
const { PrismaClient } = require("@prisma/client");
const crypto = require("crypto");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const prisma = new PrismaClient();
const app = express();
const server = http.createServer(app);

const API_VERSION = "1.5.6";
const JWT_SECRET = process.env.JWT_SECRET || "";
const isProduction = process.env.NODE_ENV === "production";
if (isProduction && (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32)) {
  throw new Error("JWT_SECRET must be configured with at least 32 characters in production");
}

const corsOrigin = process.env.CORS_ORIGIN || "*";
const allowedOrigins = corsOrigin.split(",").map(x => x.trim()).filter(Boolean);
const corsOptions = corsOrigin === "*"
  ? { origin: "*" }
  : {
      origin: (origin, callback) => {
        if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
        return callback(new Error("CORS origin not allowed"));
      },
      credentials: true
    };
app.use(cors(corsOptions));
app.use(express.json({ limit: "10mb" }));

const uploadDir = path.join(process.cwd(), "uploads");
fs.mkdirSync(uploadDir, { recursive: true });
app.use("/uploads", express.static(uploadDir));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 80 * 1024 * 1024 }
});

const asyncHandler = fn => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function cleanBaseUrl(value) {
  return String(value || "").trim().replace(/\/$/, "");
}

function parsePositiveInt(value, fallback, max) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(Math.floor(n), max);
}

const s3Ready = !!(
  process.env.S3_ENDPOINT &&
  process.env.S3_BUCKET &&
  process.env.S3_ACCESS_KEY &&
  process.env.S3_SECRET_KEY
);

const s3 = s3Ready ? new S3Client({
  region: process.env.S3_REGION || "auto",
  endpoint: process.env.S3_ENDPOINT,
  forcePathStyle: true,
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY,
    secretAccessKey: process.env.S3_SECRET_KEY
  }
}) : null;

async function storeFile(file) {
  const ext = path.extname(file.originalname || "").toLowerCase() || ".bin";
  const name = `${Date.now()}-${Math.random().toString(36).slice(2)}${ext}`;
  if (s3Ready) {
    const key = `media/${name}`;
    await s3.send(new PutObjectCommand({
      Bucket: process.env.S3_BUCKET,
      Key: key,
      Body: file.buffer,
      ContentType: file.mimetype
    }));
    const publicBase = cleanBaseUrl(process.env.S3_PUBLIC_BASE_URL);
    if (!publicBase) {
      throw new Error("S3_PUBLIC_BASE_URL is required when S3/R2 storage is enabled");
    }
    return `${publicBase}/${key}`;
  }
  const local = path.join(uploadDir, name);
  fs.writeFileSync(local, file.buffer);
  const base = (process.env.PUBLIC_BASE_URL || `http://localhost:${process.env.PORT || 4000}`).replace(/\/$/, "");
  return `${base}/uploads/${name}`;
}

function sign(user) {
  return jwt.sign(
    { id: user.id, role: user.role, username: user.username },
    JWT_SECRET,
    { expiresIn: "30d" }
  );
}

async function auth(req, res, next) {
  try {
    const raw = req.headers.authorization || "";
    const token = raw.startsWith("Bearer ") ? raw.slice(7) : null;
    if (!token) return res.status(401).json({ error: "Unauthorized" });
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
}

function admin(req, res, next) {
  if (!["ADMIN", "MODERATOR"].includes(req.user.role)) return res.status(403).json({ error: "Admin only" });
  next();
}

function safeUser(u) {
  return {
    id: u.id, username: u.username, name: u.displayName || u.name || u.username, bio: u.bio,
    avatarUrl: u.avatarUrl, phone: u.phone || null, whatsapp: u.whatsapp || null, wilaya: u.displayWilaya || null, role: u.role, isVerified: u.isVerified
  };
}

async function attachDisplayName(u) {
  if (!u) return u;
  try {
    const p = await prisma.sawtAljazairProfile.findUnique({ where: { userId: u.id } });
    return { ...u, displayName: p?.displayName || null, displayWilaya: p?.wilaya || null };
  } catch {
    return { ...u, displayName: null, displayWilaya: null };
  }
}

function publicCoords(lat, lon) {
  if (lat == null || lon == null) return {};
  return { publicLatitude: Math.round(lat * 100) / 100, publicLongitude: Math.round(lon * 100) / 100 };
}

app.get("/", (_, res) => res.json({ ok: true, service: "Sawt Aljazair API", version: API_VERSION, health: "/health" }));
app.get("/version", async (_, res) => {
  try {
    const tables = await prisma.$queryRawUnsafe(`SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('User','Post','Report') ORDER BY table_name`);
    res.json({ ok: true, service: "Sawt Aljazair API", version: API_VERSION, database: { tables: tables.map(x=>x.table_name) }, routes: ["/me/profile", "/posts", "/reports", "/reports/search"] });
  } catch (e) { res.status(503).json({ ok:false, version:API_VERSION, error:'database check failed', detail:String(e.message||e) }); }
});

app.get("/health", asyncHandler(async (_, res) => {
  await prisma.$queryRaw`SELECT 1`;
  res.json({ ok: true, version: API_VERSION, database: "ok" });
}));

function makeId(prefix = "c") {
  return `${prefix}${Date.now().toString(36)}${crypto.randomBytes(8).toString("hex")}`;
}

async function createSharedUserRaw(tx, { username, displayName, email, passwordHash }) {
  const safeDisplayName = String(displayName || username || "").trim() || username;
  if (!safeDisplayName) throw new Error("Display name is required");
  // Use an explicit SQL INSERT so a shared Prisma model cannot accidentally omit
  // the existing required User.displayName column. No schema changes are made here.
  const rows = await tx.$queryRaw`
    INSERT INTO public."User"
      ("id", "username", "displayName", "email", "passwordHash", "role", "isVerified", "createdAt")
    VALUES
      (${makeId("c")}, ${username}, ${safeDisplayName}, ${email}, ${passwordHash}, 'USER', false, CURRENT_TIMESTAMP)
    RETURNING "id", "username", "displayName", "email", "passwordHash", "role", "isVerified", "createdAt"`;
  if (!rows.length) throw new Error("User creation returned no row");
  return rows[0];
}

app.post("/auth/register", asyncHandler(async (req, res) => {
  const username = String(req.body.username || "").trim();
  const name = String(req.body.name || "").trim();
  const displayName = name || username;
  const email = String(req.body.email || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const wilaya = req.body.wilaya ? String(req.body.wilaya).trim() : null;
  if (!username || !displayName || !email || !password) return res.status(400).json({ error: "Missing fields" });
  if (username.length < 3 || username.length > 30) return res.status(400).json({ error: "Invalid username" });
  if (!/^[A-Za-z0-9_.-]+$/.test(username)) return res.status(400).json({ error: "Username contains invalid characters" });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ error: "Invalid email" });
  if (password.length < 6) return res.status(400).json({ error: "Password must be at least 6 characters" });
  const exists = await prisma.user.findFirst({ where: { OR: [{ email }, { username }] } });
  if (exists) return res.status(409).json({ error: "Username or email already exists" });
  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const result = await prisma.$transaction(async (tx) => {
      const user = await createSharedUserRaw(tx, { username, displayName, email, passwordHash });
      await tx.sawtAljazairProfile.upsert({
        where: { userId: user.id },
        create: { userId: user.id, displayName, wilaya },
        update: { displayName, wilaya }
      });
      return user;
    });
    res.status(201).json({
      token: sign(result),
      user: safeUser({ ...result, displayName, displayWilaya: wilaya })
    });
  } catch (e) {
    if (e?.code === "P2002" || e?.code === "23505" || /duplicate key/i.test(String(e?.message || ""))) {
      return res.status(409).json({ error: "Username or email already exists" });
    }
    throw e;
  }
}));

app.post("/auth/login", asyncHandler(async (req, res) => {
  const email = String(req.body.email || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) return res.status(401).json({ error: "Invalid credentials" });
  const enriched = await attachDisplayName(user);
  res.json({ token: sign(user), user: safeUser(enriched) });
}));

app.get("/me", auth, async (req, res) => {
  const u = await prisma.user.findUnique({ where: { id: req.user.id } });
  res.json({ user: safeUser(await attachDisplayName(u)) });
});

app.patch("/me/profile", auth, upload.single("avatar"), async (req, res) => {
  const displayName = String(req.body.displayName || "").trim();
  const bio = String(req.body.bio || "").trim();
  const phone = String(req.body.phone || "").trim();
  const whatsapp = String(req.body.whatsapp || "").trim();
  const wilaya = String(req.body.wilaya || "").trim();
  if (!displayName) return res.status(400).json({ error: "الاسم مطلوب" });
  if (displayName.length > 80) return res.status(400).json({ error: "الاسم طويل جدًا" });
  if (bio.length > 500) return res.status(400).json({ error: "النبذة طويلة جدًا" });
  const avatarUrl = req.file ? await storeFile(req.file) : null;
  try {
    const result = await prisma.$transaction(async (tx) => {
      const user = await tx.user.update({
        where: { id: req.user.id },
        data: { displayName, bio: bio || null, phone: phone || null, whatsapp: whatsapp || null, ...(avatarUrl ? { avatarUrl } : {}) }
      });
      const profile = await tx.sawtAljazairProfile.upsert({
        where: { userId: req.user.id },
        create: { userId: req.user.id, displayName, wilaya: wilaya || null },
        update: { displayName, wilaya: wilaya || null }
      });
      return { user, profile };
    });
    res.json({ user: safeUser({ ...result.user, displayWilaya: result.profile.wilaya }) });
  } catch (e) {
    console.error('PROFILE_UPDATE_FAILED', e);
    res.status(500).json({ error: `تعذر حفظ الملف الشخصي: ${e.message || e}` });
  }
});

app.get("/feed", auth, async (req, res) => {
  const { wilaya, limit = 30 } = req.query;
  const posts = await prisma.post.findMany({
    where: wilaya ? { wilaya } : {},
    orderBy: { createdAt: "desc" },
    take: parsePositiveInt(limit, 30, 50),
    include: {
      author: true,
      _count: { select: { likes: true, comments: true, saves: true } }
    }
  });
  res.json(posts.map(p => ({
    ...p, author: safeUser(p.author)
  })));
});

app.post("/posts", auth, upload.single("media"), async (req, res) => {
  try {
    const { title, wilaya, city, latitude, longitude } = req.body;
    const body = String(req.body.body || "").trim();
    if (!body) return res.status(400).json({ error: "Post body cannot be empty" });
    const mediaUrl = req.file ? await storeFile(req.file) : null;
    const mediaType = req.file?.mimetype?.startsWith("video") ? "VIDEO" : req.file ? "IMAGE" : null;
    const post = await prisma.post.create({
      data: {
        authorId: req.user.id, title, body, wilaya, city,
        latitude: latitude ? Number(latitude) : null,
        longitude: longitude ? Number(longitude) : null,
        mediaUrl, mediaType
      },
      include: { author: true }
    });
    res.json({ ...post, author: safeUser(post.author) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/posts/:id/like", auth, async (req, res) => {
  const where = { userId_postId: { userId: req.user.id, postId: req.params.id } };
  const old = await prisma.like.findUnique({ where });
  if (old) await prisma.like.delete({ where });
  else await prisma.like.create({ data: { userId: req.user.id, postId: req.params.id } });
  res.json({ liked: !old });
});

app.post("/posts/:id/save", auth, async (req, res) => {
  const where = { userId_postId: { userId: req.user.id, postId: req.params.id } };
  const old = await prisma.save.findUnique({ where });
  if (old) await prisma.save.delete({ where });
  else await prisma.save.create({ data: { userId: req.user.id, postId: req.params.id } });
  res.json({ saved: !old });
});

app.get("/posts/:id/comments", async (req, res) => {
  const comments = await prisma.comment.findMany({
    where: { postId: req.params.id }, orderBy: { createdAt: "asc" }, include: { user: true }
  });
  res.json(comments.map(c => ({ ...c, user: safeUser(c.user) })));
});

app.post("/posts/:id/comments", auth, async (req, res) => {
  const comment = await prisma.comment.create({
    data: { postId: req.params.id, userId: req.user.id, body: String(req.body.body || "").trim().slice(0, 2000) },
    include: { user: true }
  });
  res.json({ ...comment, user: safeUser(comment.user) });
});

app.post("/reports", auth, upload.array("media", 6), async (req, res) => {
  try {
    const { type, title, description, wilaya, city, latitude, longitude, anonymous } = req.body;
    if (!type || !title || !description || !wilaya) return res.status(400).json({ error: "Missing report fields" });
    const files = req.files || [];
    const first = files[0] ? await storeFile(files[0]) : null;
    const mediaType = files[0]?.mimetype?.startsWith("video") ? "VIDEO" : files[0] ? "IMAGE" : null;
    const lat = latitude ? Number(latitude) : null;
    const lon = longitude ? Number(longitude) : null;
    const report = await prisma.report.create({
      data: {
        reporterId: req.user.id, type, title, description, wilaya, city,
        latitude: lat, longitude: lon, ...publicCoords(lat, lon),
        mediaUrl: first, mediaType, anonymous: anonymous === "true" || anonymous === true,
        evidence: {
          create: (await Promise.all(files.slice(1).map(async f => ({
            url: await storeFile(f),
            type: f.mimetype?.startsWith("video") ? "VIDEO" : "IMAGE"
          })))).map(x => ({ url: x.url, type: x.type }))
        }
      },
      include: { reporter: true, evidence: true }
    });
    res.json({
      ...report,
      reporter: report.anonymous ? null : safeUser(report.reporter),
      latitude: report.publicLatitude,
      longitude: report.publicLongitude
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/reports", auth, async (req, res) => {
  const { wilaya, type, status, limit = 100 } = req.query;
  const reports = await prisma.report.findMany({
    where: {
      ...(wilaya ? { wilaya } : {}),
      ...(type ? { type } : {}),
      ...(status ? { status } : {})
    },
    orderBy: { createdAt: "desc" }, take: parsePositiveInt(limit, 100, 200),
    include: { evidence: true, reporter: true }
  });
  res.json(reports.map(r => ({
    ...r,
    latitude: r.publicLatitude,
    longitude: r.publicLongitude,
    reporter: r.anonymous ? null : (r.reporter ? safeUser(r.reporter) : null)
  })));
});

app.get("/reports/search", auth, async (req, res) => {
  const q = String(req.query.q || "");
  const reports = await prisma.report.findMany({
    where: {
      AND: [
        q ? { OR: [{ title: { contains: q, mode: "insensitive" } }, { description: { contains: q, mode: "insensitive" } }] } : {},
        req.query.wilaya ? { wilaya: req.query.wilaya } : {},
        req.query.type ? { type: req.query.type } : {},
        req.query.status ? { status: req.query.status } : {}
      ]
    },
    orderBy: { createdAt: "desc" }, take: 100
  });
  res.json(reports.map(r => ({ ...r, latitude: r.publicLatitude, longitude: r.publicLongitude })));
});

app.get("/reports/:id", auth, async (req, res) => {
  const r = await prisma.report.findUnique({ where: { id: req.params.id }, include: { evidence: true, reporter: true } });
  if (!r) return res.status(404).json({ error: "Not found" });
  res.json({ ...r, latitude: r.publicLatitude, longitude: r.publicLongitude, reporter: r.anonymous ? null : (r.reporter ? safeUser(r.reporter) : null) });
});

app.patch("/reports/:id/status", auth, async (req, res) => {
  if (!["ADMIN", "MODERATOR"].includes(req.user.role)) return res.status(403).json({ error: "Admin only" });
  const allowed = ["PENDING", "REVIEWED", "VERIFIED", "RESOLVED", "REJECTED"];
  if (!allowed.includes(req.body.status)) return res.status(400).json({ error: "Invalid report status" });
  const r = await prisma.report.update({
    where: { id: req.params.id },
    data: { status: req.body.status, moderatorNote: req.body.note || null }
  });
  res.json(r);
});

app.post("/reports/:id/evidence", auth, upload.array("media", 6), async (req, res) => {
  const files = req.files || [];
  const rows = [];
  for (const f of files) {
    rows.push(await prisma.evidence.create({
      data: { reportId: req.params.id, url: await storeFile(f), type: f.mimetype?.startsWith("video") ? "VIDEO" : "IMAGE" }
    }));
  }
  res.json(rows);
});

app.post("/lost-found", auth, upload.single("image"), async (req, res) => {
  const imageUrl = req.file ? await storeFile(req.file) : null;
  const item = await prisma.lostFound.create({
    data: {
      userId: req.user.id, kind: req.body.kind || "LOST",
      title: req.body.title, description: req.body.description,
      category: req.body.category, wilaya: req.body.wilaya, city: req.body.city,
      latitude: req.body.latitude ? Number(req.body.latitude) : null,
      longitude: req.body.longitude ? Number(req.body.longitude) : null,
      imageUrl, contactHint: req.body.contactHint
    }
  });
  res.json(item);
});

app.get("/lost-found", auth, async (req, res) => {
  const items = await prisma.lostFound.findMany({ orderBy: { createdAt: "desc" }, take: 100 });
  res.json(items);
});

app.get("/lost-found/matches/:id", auth, async (req, res) => {
  const item = await prisma.lostFound.findUnique({ where: { id: req.params.id } });
  if (!item) return res.status(404).json({ error: "Not found" });
  const matches = await prisma.lostFound.findMany({
    where: {
      id: { not: item.id },
      category: item.category,
      wilaya: item.wilaya
    },
    orderBy: { createdAt: "desc" },
    take: 20
  });
  res.json(matches);
});

app.post("/verification/request", auth, upload.single("document"), async (req, res) => {
  const documentUrl = req.file ? await storeFile(req.file) : null;
  const row = await prisma.verificationRequest.upsert({
    where: { userId: req.user.id },
    update: { reason: req.body.reason || "", documentUrl, status: "PENDING", note: null },
    create: { userId: req.user.id, reason: req.body.reason || "", documentUrl }
  });
  res.json(row);
});

app.get("/verification/me", auth, async (req, res) => {
  res.json(await prisma.verificationRequest.findUnique({ where: { userId: req.user.id } }));
});

app.get("/admin/verification", auth, admin, async (_, res) => {
  const rows = await prisma.verificationRequest.findMany({ include: { user: true }, orderBy: { createdAt: "desc" } });
  res.json(rows.map(r => ({ ...r, user: safeUser(r.user) })));
});

app.patch("/admin/verification/:id", auth, admin, async (req, res) => {
  const row = await prisma.verificationRequest.update({
    where: { id: req.params.id },
    data: { status: req.body.status, note: req.body.note || null }
  });
  if (req.body.status === "APPROVED") await prisma.user.update({ where: { id: row.userId }, data: { isVerified: true } });
  if (req.body.status === "REJECTED") await prisma.user.update({ where: { id: row.userId }, data: { isVerified: false } });
  res.json(row);
});

app.get("/admin/reports", auth, admin, async (_, res) => {
  const rows = await prisma.report.findMany({ orderBy: { createdAt: "desc" }, take: 200, include: { reporter: true } });
  res.json(rows.map(r => ({ ...r, reporter: r.anonymous ? null : (r.reporter ? safeUser(r.reporter) : null) })));
});

app.get("/admin/stats", auth, admin, async (_, res) => {
  const [users, posts, reports, pendingReports, verifiedUsers, lostFound] = await Promise.all([
    prisma.user.count(), prisma.post.count(), prisma.report.count(),
    prisma.report.count({ where: { status: "PENDING" } }),
    prisma.user.count({ where: { isVerified: true } }),
    prisma.lostFound.count()
  ]);
  res.json({ users, posts, reports, pendingReports, verifiedUsers, lostFound });
});

app.get("/conversations", auth, async (req, res) => {
  const rows = await prisma.conversation.findMany({
    where: { members: { some: { userId: req.user.id } } },
    include: { members: { include: { user: true } }, messages: { orderBy: { createdAt: "desc" }, take: 1 } },
    orderBy: { createdAt: "desc" }
  });
  res.json(rows.map(c => ({
    id: c.id,
    members: c.members.map(m => ({ ...m, user: safeUser(m.user) })),
    lastMessage: c.messages[0] || null
  })));
});

app.post("/conversations", auth, async (req, res) => {
  const otherId = req.body.userId;
  if (!otherId || otherId === req.user.id) return res.status(400).json({ error: "Invalid user" });
  const existing = await prisma.conversation.findFirst({
    where: {
      AND: [
        { members: { some: { userId: req.user.id } } },
        { members: { some: { userId: otherId } } }
      ]
    },
    include: { members: true }
  });
  if (existing && existing.members.length === 2) return res.json(existing);
  const c = await prisma.conversation.create({
    data: { members: { create: [{ userId: req.user.id }, { userId: otherId }] } }
  });
  res.json(c);
});

app.get("/conversations/:id/messages", auth, async (req, res) => {
  const member = await prisma.conversationMember.findFirst({ where: { conversationId: req.params.id, userId: req.user.id } });
  if (!member) return res.status(403).json({ error: "Forbidden" });
  const rows = await prisma.message.findMany({
    where: { conversationId: req.params.id }, orderBy: { createdAt: "asc" }, take: 300,
    include: { sender: true }
  });
  res.json(rows.map(m => ({ ...m, sender: safeUser(m.sender) })));
});

app.post("/conversations/:id/messages", auth, async (req, res) => {
  const member = await prisma.conversationMember.findFirst({ where: { conversationId: req.params.id, userId: req.user.id } });
  if (!member) return res.status(403).json({ error: "Forbidden" });
  const blocked = await prisma.block.findFirst({
    where: { conversationId: req.params.id, OR: [{ blockerId: req.user.id }, { blockedId: req.user.id }] }
  });
  if (blocked) return res.status(403).json({ error: "Conversation is blocked" });
  const body = String(req.body.body || "").trim();
  if (!body) return res.status(400).json({ error: "Message cannot be empty" });
  const msg = await prisma.message.create({
    data: { conversationId: req.params.id, senderId: req.user.id, body: body.slice(0, 5000) },
    include: { sender: true }
  });
  io.to(`conversation:${req.params.id}`).emit("message:new", { ...msg, sender: safeUser(msg.sender) });
  res.json({ ...msg, sender: safeUser(msg.sender) });
});

app.patch("/conversations/:id/read", auth, async (req, res) => {
  await prisma.conversationMember.updateMany({
    where: { conversationId: req.params.id, userId: req.user.id },
    data: { lastReadAt: new Date() }
  });
  await prisma.message.updateMany({
    where: { conversationId: req.params.id, senderId: { not: req.user.id }, readAt: null },
    data: { readAt: new Date() }
  });
  res.json({ ok: true });
});

app.post("/conversations/:id/block", auth, async (req, res) => {
  const otherId = req.body.userId;
  await prisma.block.create({ data: { conversationId: req.params.id, blockerId: req.user.id, blockedId: otherId } }).catch(() => {});
  res.json({ ok: true });
});

app.post("/conversations/:id/report", auth, async (req, res) => {
  const text = `بلاغ محادثة ${req.params.id}: ${String(req.body.reason || "").slice(0, 500)}`;
  await prisma.notification.create({ data: { userId: req.user.id, title: "تم إرسال البلاغ", body: text } });
  res.json({ ok: true });
});

app.get("/users/search", auth, async (req, res) => {
  const q = String(req.query.q || "");
  const rows = await prisma.user.findMany({
    where: { username: { contains: q, mode: "insensitive" } },
    take: 30
  });
  res.json(rows.map(safeUser));
});

app.get("/users/:id", auth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: "User not found" });
  const enriched = await attachDisplayName(user);
  res.json({ user: safeUser(enriched) });
});

app.post("/follow/:id", auth, async (req, res) => {
  const followingId = req.params.id;
  const where = { followerId_followingId: { followerId: req.user.id, followingId } };
  const old = await prisma.follow.findUnique({ where });
  if (old) await prisma.follow.delete({ where });
  else await prisma.follow.create({ data: { followerId: req.user.id, followingId } });
  res.json({ following: !old });
});

app.get("/notifications", auth, async (req, res) => {
  const rows = await prisma.notification.findMany({ where: { userId: req.user.id }, orderBy: { createdAt: "desc" }, take: 50 });
  res.json(rows.map(n => ({ ...n, title: n.title || "إشعار", body: n.body || "" })));
});

const io = new Server(server, { cors: corsOptions });
io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    socket.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch { next(new Error("Unauthorized")); }
});
io.on("connection", socket => {
  socket.on("conversation:join", id => socket.join(`conversation:${id}`));
  socket.on("typing", id => socket.to(`conversation:${id}`).emit("typing", { userId: socket.user.id }));
});

app.use((req, res) => res.status(404).json({ error: "Route not found" }));
app.use((err, req, res, next) => {
  console.error(err);
  if (res.headersSent) return next(err);
  const status = Number(err.statusCode || err.status || 500);
  res.status(status >= 400 && status < 600 ? status : 500).json({ error: isProduction ? "Internal server error" : String(err.message || err) });
});

process.on("unhandledRejection", err => console.error("Unhandled rejection:", err));
process.on("uncaughtException", err => console.error("Uncaught exception:", err));

async function seedTestAccountIfConfigured() {
  const email = String(process.env.TEST_ACCOUNT_EMAIL || "").trim().toLowerCase();
  const password = String(process.env.TEST_ACCOUNT_PASSWORD || "");
  if (!email || !password) return;
  const username = String(process.env.TEST_ACCOUNT_USERNAME || "sawt_test_2026").trim();
  const displayName = String(process.env.TEST_ACCOUNT_NAME || "Sawt Aljazair Test").trim() || username;
  const wilaya = String(process.env.TEST_ACCOUNT_WILAYA || "وهران").trim() || null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 6) {
    throw new Error("Invalid TEST_ACCOUNT_EMAIL or TEST_ACCOUNT_PASSWORD");
  }
  const passwordHash = await bcrypt.hash(password, 12);
  const existing = await prisma.user.findFirst({ where: { OR: [{ email }, { username }] } });
  if (existing) {
    console.log(`Test account already exists: ${email}`);
    return;
  }
  await prisma.$transaction(async tx => {
    const user = await createSharedUserRaw(tx, { username, displayName, email, passwordHash });
    await tx.sawtAljazairProfile.upsert({
      where: { userId: user.id },
      create: { userId: user.id, displayName, wilaya },
      update: { displayName, wilaya }
    });
  });
  console.log(`Test account created: ${email} / [password supplied via TEST_ACCOUNT_PASSWORD]`);
}

const port = Number(process.env.PORT || 4000);
prisma.$connect()
  .then(async () => {
    await seedTestAccountIfConfigured();
    server.listen(port, () => console.log(`Sawt AlJazair API V${API_VERSION} running on :${port}`));
  })
  .catch(err => { console.error("Database connection failed:", err); process.exit(1); });
