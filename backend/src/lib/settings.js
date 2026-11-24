const prisma = require("./prisma");

const DEFAULTS = {
  requireReportReview: "true",   // public lists only show reviewed reports
  registrationOpen: "true",
  maintenance: "false",
  announcement: "",
  announcementLevel: "info",     // info | warning | critical
  allowAnonymousReports: "true",
  minAppVersion: ""
};

let cache = null;
let cacheAt = 0;

async function all() {
  if (cache && Date.now() - cacheAt < 10000) return cache;
  const out = { ...DEFAULTS };
  try {
    const rows = await prisma.appSetting.findMany();
    for (const r of rows) if (r.key in DEFAULTS) out[r.key] = r.value;
  } catch (e) {
    console.error("settings load failed", e.message);
  }
  cache = out;
  cacheAt = Date.now();
  return out;
}

async function get(key) {
  return (await all())[key];
}

async function set(key, value) {
  if (!(key in DEFAULTS)) return false;
  const v = String(value ?? "");
  await prisma.appSetting.upsert({ where: { key }, create: { key, value: v }, update: { value: v } });
  cache = null;
  return true;
}

const isTrue = (v) => String(v).toLowerCase() === "true";

async function publicSettings() {
  const s = await all();
  return {
    announcement: s.announcement,
    announcementLevel: s.announcementLevel,
    maintenance: isTrue(s.maintenance),
    registrationOpen: isTrue(s.registrationOpen),
    allowAnonymousReports: isTrue(s.allowAnonymousReports),
    minAppVersion: s.minAppVersion
  };
}

module.exports = { DEFAULTS, all, get, set, isTrue, publicSettings };
