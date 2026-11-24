const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { Server } = require("socket.io");

const cfg = require("./lib/config");
const prisma = require("./lib/prisma");
const settings = require("./lib/settings");
const { loadAuthUser, verifySocketToken } = require("./lib/auth");
const { setIO, getFcm } = require("./lib/notify");
const { serveMedia, uploadDir, backend: storageBackend } = require("./lib/storage");
const { asyncHandler } = require("./lib/util");

const app = express();
const server = http.createServer(app);

app.set("trust proxy", 1);
app.disable("x-powered-by");

const allowedOrigins = cfg.corsOrigin.split(",").map((x) => x.trim()).filter(Boolean);
const corsOptions = cfg.corsOrigin === "*"
  ? { origin: "*" }
  : {
      origin: (origin, callback) => {
        if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
        return callback(new Error("CORS origin not allowed"));
      },
      credentials: true
    };
app.use(cors(corsOptions));
app.use((_req, res, next) => {
  res.set({ "X-Content-Type-Options": "nosniff", "X-Frame-Options": "SAMEORIGIN", "Referrer-Policy": "no-referrer" });
  next();
});
app.use(express.json({ limit: "1mb" }));
// Express 5 leaves req.body undefined when nothing parsed it.
app.use((req, _res, next) => { if (req.body === undefined) req.body = {}; next(); });

// ---- static / media ----
fs.mkdirSync(uploadDir, { recursive: true });
app.use("/uploads", express.static(uploadDir, { maxAge: "30d", setHeaders: (res) => res.set("Cross-Origin-Resource-Policy", "cross-origin") }));
app.get("/media/:file", asyncHandler(serveMedia));
app.use("/panel", express.static(path.join(__dirname, "..", "public", "admin"), { maxAge: 0, index: "index.html" }));

// ---- health ----
app.get("/", (_req, res) => res.json({ ok: true, service: "Sawt Aljazair API", version: cfg.API_VERSION, health: "/health", adminPanel: "/panel" }));
app.get("/health", asyncHandler(async (_req, res) => {
  await prisma.$queryRaw`SELECT 1`;
  res.json({ ok: true, version: cfg.API_VERSION, database: "ok", storage: storageBackend(), push: !!getFcm() });
}));
app.get("/version", (_req, res) => res.json({ ok: true, service: "Sawt Aljazair API", version: cfg.API_VERSION }));

// ---- maintenance mode (staff and auth endpoints stay available) ----
app.use(asyncHandler(async (req, res, next) => {
  const exempt = ["/health", "/version", "/settings/public", "/auth/login", "/panel"];
  if (exempt.some((p) => req.path === p || req.path.startsWith(`${p}/`)) || req.path.startsWith("/admin")) return next();
  if (!settings.isTrue(await settings.get("maintenance"))) return next();
  try {
    const raw = req.headers.authorization || "";
    const payload = raw.startsWith("Bearer ") ? jwt.verify(raw.slice(7), cfg.JWT_SECRET) : null;
    if (payload && ["ADMIN", "MODERATOR"].includes(payload.role)) return next();
  } catch { /* fall through */ }
  return res.status(503).json({ code: "MAINTENANCE", error: "The service is under maintenance" });
}));

// ---- routes ----
app.use(require("./routes/auth"));
app.use(require("./routes/me"));
app.use(require("./routes/social"));
app.use(require("./routes/posts"));
app.use(require("./routes/reports"));
app.use(require("./routes/lostfound"));
app.use(require("./routes/verification"));
app.use(require("./routes/chat"));
app.use(require("./routes/notifications"));
app.use(require("./routes/admin"));

app.use((_req, res) => res.status(404).json({ code: "NOT_FOUND", error: "Route not found" }));
app.use((err, _req, res, next) => {
  if (res.headersSent) return next(err);
  let status = Number(err.status || err.statusCode || 500);
  let code = err.code && typeof err.code === "string" && /^[A-Z_]+$/.test(err.code) ? err.code : undefined;
  if (err.code === "LIMIT_FILE_SIZE") { status = 413; code = "FILE_TOO_LARGE"; }
  else if (err.code === "LIMIT_FILE_COUNT" || err.code === "LIMIT_UNEXPECTED_FILE") { status = 400; code = "TOO_MANY_FILES"; }
  else if (err.type === "entity.parse.failed") { status = 400; code = "BAD_JSON"; }
  else if (err.type === "entity.too.large") { status = 413; code = "PAYLOAD_TOO_LARGE"; }
  if (!(status >= 400 && status < 600)) status = 500;
  if (status >= 500) console.error(err);
  const message = status < 500 ? String(err.message || "Invalid request") : (cfg.isProduction ? "Internal server error" : String(err.message || err));
  res.status(status).json({ code: code || (status >= 500 ? "SERVER_ERROR" : "BAD_REQUEST"), error: message });
});

// ---- realtime ----
const io = new Server(server, { cors: corsOptions, maxHttpBufferSize: 1e6 });
setIO(io);
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth && socket.handshake.auth.token;
    const payload = verifySocketToken(token);
    const u = await loadAuthUser(payload.id);
    if (!u || u.banned) return next(new Error("Unauthorized"));
    socket.user = { id: u.id, role: u.role, username: u.username };
    next();
  } catch { next(new Error("Unauthorized")); }
});
io.on("connection", (socket) => {
  socket.join(`user:${socket.user.id}`);
  socket.on("conversation:join", async (id) => {
    try {
      const m = await prisma.conversationMember.findFirst({ where: { conversationId: String(id), userId: socket.user.id }, select: { id: true } });
      if (m) socket.join(`conversation:${id}`);
    } catch { /* ignore */ }
  });
  socket.on("conversation:leave", (id) => socket.leave(`conversation:${id}`));
  socket.on("typing", (id) => {
    const room = `conversation:${id}`;
    if (socket.rooms.has(room)) socket.to(room).emit("typing", { userId: socket.user.id, conversationId: String(id) });
  });
});

process.on("unhandledRejection", (err) => console.error("Unhandled rejection:", err));
process.on("uncaughtException", (err) => console.error("Uncaught exception:", err));

// ---- startup seeding ----
async function seedAccount({ email, password, username, name, wilaya, role }) {
  email = String(email || "").trim().toLowerCase();
  password = String(password || "");
  if (!email || !password) return;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 6) throw new Error(`Invalid seed account credentials for ${email}`);
  username = String(username).trim();
  const existing = await prisma.user.findFirst({ where: { OR: [{ email }, { username }] } });
  if (existing) {
    if (role && existing.role !== role) await prisma.user.update({ where: { id: existing.id }, data: { role } });
    console.log(`Seed account already exists: ${email}`);
    return;
  }
  const passwordHash = await bcrypt.hash(password, 12);
  const displayName = String(name || username).trim() || username;
  const user = await prisma.user.create({ data: { username, displayName, email, passwordHash, role: role || "USER", isVerified: role === "ADMIN" } });
  await prisma.sawtAljazairProfile.upsert({
    where: { userId: user.id }, create: { userId: user.id, displayName, wilaya: wilaya || null }, update: { displayName, wilaya: wilaya || null }
  });
  console.log(`Seed account created: ${email} (${role || "USER"})`);
}

async function startupTasks() {
  if (cfg.adminEmails.length) {
    const r = await prisma.user.updateMany({ where: { email: { in: cfg.adminEmails }, role: { not: "ADMIN" } }, data: { role: "ADMIN" } });
    if (r.count) console.log(`Promoted ${r.count} account(s) to ADMIN from ADMIN_EMAILS`);
  }
  await seedAccount({
    email: process.env.ADMIN_SEED_EMAIL, password: process.env.ADMIN_SEED_PASSWORD,
    username: process.env.ADMIN_SEED_USERNAME || "admin", name: process.env.ADMIN_SEED_NAME || "Administrator",
    wilaya: process.env.ADMIN_SEED_WILAYA || "الجزائر", role: "ADMIN"
  });
  await seedAccount({
    email: process.env.TEST_ACCOUNT_EMAIL, password: process.env.TEST_ACCOUNT_PASSWORD,
    username: process.env.TEST_ACCOUNT_USERNAME || "sawt_test_2026", name: process.env.TEST_ACCOUNT_NAME || "Sawt Aljazair Test",
    wilaya: process.env.TEST_ACCOUNT_WILAYA || "وهران", role: "USER"
  });
}

prisma.$connect()
  .then(async () => {
    try { await startupTasks(); } catch (e) { console.error("Startup tasks failed (server will still start):", e.message); }
    server.listen(cfg.PORT, () => {
      console.log(`Sawt AlJazair API v${cfg.API_VERSION} on :${cfg.PORT} | storage=${storageBackend()} | push=${getFcm() ? "fcm" : "off"}`);
    });
  })
  .catch((err) => { console.error("Database connection failed:", err); process.exit(1); });
