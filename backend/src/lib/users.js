const prisma = require("./prisma");

// Never select passwordHash/email for public output.
const USER_SELECT = {
  id: true, username: true, displayName: true, bio: true, avatarUrl: true,
  phone: true, whatsapp: true, role: true, isVerified: true, createdAt: true
};

async function profileMap(ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  if (!unique.length) return new Map();
  let rows = [];
  try {
    rows = await prisma.sawtAljazairProfile.findMany({ where: { userId: { in: unique } } });
  } catch (e) {
    console.error("profileMap failed", e.message);
  }
  return new Map(rows.map((r) => [r.userId, r]));
}

function shape(u, p, admin = false) {
  if (!u) return null;
  const out = {
    id: u.id,
    username: u.username,
    name: (p && p.displayName) || u.displayName || u.username,
    bio: u.bio || null,
    avatarUrl: u.avatarUrl || null,
    phone: u.phone || null,
    whatsapp: u.whatsapp || null,
    wilaya: (p && p.wilaya) || null,
    role: u.role,
    isVerified: !!u.isVerified,
    createdAt: u.createdAt
  };
  if (admin) {
    out.email = u.email || null;
    out.banned = !!(p && p.banned);
    out.bannedReason = (p && p.bannedReason) || null;
    out.lastSeenAt = (p && p.lastSeenAt) || null;
    out.language = (p && p.language) || null;
  }
  return out;
}

async function toUsers(users, admin = false) {
  const map = await profileMap(users.map((u) => u && u.id));
  return users.map((u) => shape(u, u ? map.get(u.id) : null, admin));
}

async function toUser(u, admin = false) {
  if (!u) return null;
  return (await toUsers([u], admin))[0];
}

async function languageOf(userId) {
  try {
    const p = await prisma.sawtAljazairProfile.findUnique({ where: { userId }, select: { language: true } });
    return (p && p.language) || "ar";
  } catch { return "ar"; }
}

module.exports = { USER_SELECT, profileMap, shape, toUsers, toUser, languageOf };
