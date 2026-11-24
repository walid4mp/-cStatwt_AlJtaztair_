const prisma = require("./prisma");
const { text, statusLabel } = require("./i18n");
const { languageOf } = require("./users");

let io = null;
function setIO(instance) { io = instance; }
function getIO() { return io; }

// ---- optional Firebase Cloud Messaging (true background push) ----
let fcm = undefined; // undefined = not tried, null = unavailable
function getFcm() {
  if (fcm !== undefined) return fcm;
  fcm = null;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return fcm;
  try {
    const admin = require("firebase-admin");
    const cred = JSON.parse(raw.trim().startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8"));
    if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(cred) });
    fcm = admin.messaging();
    console.log("[push] Firebase Cloud Messaging enabled");
  } catch (e) {
    console.warn("[push] FCM disabled:", e.message);
  }
  return fcm;
}

async function sendPush(userIds, { title, body, data }) {
  const m = getFcm();
  if (!m || !userIds.length) return;
  try {
    const rows = await prisma.deviceToken.findMany({ where: { userId: { in: userIds } }, select: { token: true } });
    if (!rows.length) return;
    const tokens = rows.map((r) => r.token);
    const strData = {};
    for (const [k, v] of Object.entries(data || {})) strData[k] = String(v);
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const res = await m.sendEachForMulticast({
        tokens: chunk,
        notification: { title, body },
        data: strData,
        android: { priority: "high", notification: { channelId: "sawt_general" } }
      });
      const dead = [];
      res.responses.forEach((r, idx) => {
        const code = r.error && r.error.code;
        if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") dead.push(chunk[idx]);
      });
      if (dead.length) await prisma.deviceToken.deleteMany({ where: { token: { in: dead } } });
    }
  } catch (e) {
    console.error("[push] send failed", e.message);
  }
}

function emitUser(userId, event, payload) {
  if (io) io.to(`user:${userId}`).emit(event, payload);
}

/**
 * Create an in-app notification, emit it in real time and push it (if FCM is configured).
 * `kind` + `vars` produce a localized text; pass `raw: {title, body}` for custom text.
 */
async function notify(userId, kind, vars = {}, { data = {}, raw = null, push = true } = {}) {
  try {
    let title, body;
    if (raw) { title = raw.title; body = raw.body; }
    else {
      const lang = await languageOf(userId);
      const v = { ...vars };
      if (v.status) v.status = statusLabel(lang, v.status);
      [title, body] = text(lang, kind, v);
    }
    const row = await prisma.notification.create({ data: { userId, type: kind, title, body, data } });
    emitUser(userId, "notification:new", row);
    if (push) sendPush([userId], { title, body, data: { type: kind, notificationId: row.id, ...data } });
    return row;
  } catch (e) {
    console.error("notify failed", e.message);
    return null;
  }
}

async function notifyStaff(kind, vars = {}, data = {}) {
  try {
    const staffRows = await prisma.user.findMany({ where: { role: { in: ["ADMIN", "MODERATOR"] } }, select: { id: true } });
    await Promise.all(staffRows.map((s) => notify(s.id, kind, vars, { data })));
  } catch (e) {
    console.error("notifyStaff failed", e.message);
  }
}

module.exports = { setIO, getIO, notify, notifyStaff, sendPush, emitUser, getFcm };
