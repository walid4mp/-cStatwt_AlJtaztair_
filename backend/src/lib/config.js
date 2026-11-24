const crypto = require("crypto");

const isProduction = process.env.NODE_ENV === "production";
let JWT_SECRET = process.env.JWT_SECRET || "";
if (isProduction && JWT_SECRET.length < 32) {
  throw new Error("JWT_SECRET must be configured with at least 32 characters in production");
}
if (!JWT_SECRET) {
  // Development only: random per-process secret (tokens stop working after restart).
  JWT_SECRET = crypto.randomBytes(32).toString("hex");
  console.warn("[config] JWT_SECRET is not set; using a temporary development secret.");
}

const list = (v) => String(v || "").split(",").map((x) => x.trim()).filter(Boolean);

module.exports = {
  API_VERSION: "2.0.0",
  isProduction,
  JWT_SECRET,
  PORT: Number(process.env.PORT || 4000),
  corsOrigin: process.env.CORS_ORIGIN || "*",
  adminEmails: list(process.env.ADMIN_EMAILS).map((x) => x.toLowerCase()),
  maxUploadBytes: Number(process.env.MAX_UPLOAD_BYTES || 50 * 1024 * 1024),
  dbMediaMaxBytes: Number(process.env.DB_MEDIA_MAX_BYTES || 40 * 1024 * 1024),
  storageMode: String(process.env.STORAGE_MODE || "auto").toLowerCase(), // auto | s3 | db | local
  publicBaseUrl: String(process.env.PUBLIC_BASE_URL || "").trim().replace(/\/$/, ""),
  languages: ["ar", "fr", "en"],
  smtp: {
    host: process.env.SMTP_HOST || "",
    port: Number(process.env.SMTP_PORT || 587),
    user: process.env.SMTP_USER || "",
    pass: process.env.SMTP_PASS || "",
    from: process.env.SMTP_FROM || process.env.SMTP_USER || "no-reply@sawt-aljazair.local"
  }
};
