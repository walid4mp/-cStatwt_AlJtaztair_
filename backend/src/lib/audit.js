const prisma = require("./prisma");

async function audit(actor, action, targetType, targetId, detail) {
  try {
    await prisma.auditLog.create({
      data: {
        actorId: actor.id,
        actorName: actor.username || null,
        action,
        targetType: targetType || null,
        targetId: targetId || null,
        detail: detail ? String(detail).slice(0, 500) : null
      }
    });
  } catch (e) {
    console.error("audit failed", e.message);
  }
}

module.exports = { audit };
