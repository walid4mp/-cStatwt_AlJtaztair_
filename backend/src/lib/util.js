const crypto = require("crypto");

class HttpError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.status = status;
    this.code = code;
  }
}
const httpError = (status, code, message) => new HttpError(status, code, message);

const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function makeId(prefix = "c") {
  return `${prefix}${Date.now().toString(36)}${crypto.randomBytes(8).toString("hex")}`;
}

function clampInt(value, fallback, max, min = 1) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min) return fallback;
  return Math.min(Math.floor(n), max);
}

function str(value, max = 5000) {
  if (value === undefined || value === null) return "";
  return String(value).trim().slice(0, max);
}

function optStr(value, max = 5000) {
  const s = str(value, max);
  return s ? s : null;
}

function coord(value, min, max) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}
const lat = (v) => coord(v, -90, 90);
const lon = (v) => coord(v, -180, 180);

function bool(v) {
  return v === true || v === "true" || v === "1" || v === 1;
}

function parseDate(v) {
  if (!v) return null;
  const d = new Date(String(v));
  return Number.isNaN(d.getTime()) ? null : d;
}

// Public (blurred) coordinates, ~1.1 km precision.
function publicCoords(la, lo) {
  if (la == null || lo == null) return {};
  return { publicLatitude: Math.round(la * 100) / 100, publicLongitude: Math.round(lo * 100) / 100 };
}

function randomCode(len = 6) {
  let s = "";
  for (let i = 0; i < len; i++) s += crypto.randomInt(0, 10);
  return s;
}

function sha(v) {
  return crypto.createHash("sha256").update(String(v)).digest("hex");
}

// Tiny in-memory rate limiter (per process).
function rateLimit({ windowMs, max, key }) {
  const hits = new Map();
  setInterval(() => {
    const now = Date.now();
    for (const [k, v] of hits) if (v.reset <= now) hits.delete(k);
  }, Math.max(windowMs, 60000)).unref();
  return (req, res, next) => {
    const k = key ? key(req) : req.ip;
    const now = Date.now();
    let e = hits.get(k);
    if (!e || e.reset <= now) { e = { count: 0, reset: now + windowMs }; hits.set(k, e); }
    e.count++;
    if (e.count > max) {
      res.set("Retry-After", String(Math.ceil((e.reset - now) / 1000)));
      return res.status(429).json({ code: "RATE_LIMITED", error: "Too many attempts. Try again later." });
    }
    next();
  };
}

module.exports = { HttpError, httpError, asyncHandler, makeId, clampInt, str, optStr, lat, lon, bool, parseDate, publicCoords, randomCode, sha, rateLimit };
