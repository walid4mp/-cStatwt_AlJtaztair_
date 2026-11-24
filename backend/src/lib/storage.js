const path = require("path");
const fs = require("fs");
const prisma = require("./prisma");
const cfg = require("./config");
const { httpError, makeId } = require("./util");

const uploadDir = path.join(process.cwd(), "uploads");
const s3Ready = !!(process.env.S3_ENDPOINT && process.env.S3_BUCKET && process.env.S3_ACCESS_KEY && process.env.S3_SECRET_KEY);
const s3PublicBase = String(process.env.S3_PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");

let s3 = null;
let PutObjectCommand = null;
if (s3Ready) {
  const { S3Client, PutObjectCommand: Put } = require("@aws-sdk/client-s3");
  PutObjectCommand = Put;
  s3 = new S3Client({
    region: process.env.S3_REGION || "auto",
    endpoint: process.env.S3_ENDPOINT,
    forcePathStyle: true,
    credentials: { accessKeyId: process.env.S3_ACCESS_KEY, secretAccessKey: process.env.S3_SECRET_KEY }
  });
}

function backend() {
  const m = cfg.storageMode;
  if (m === "s3") return s3Ready && s3PublicBase ? "s3" : "db";
  if (m === "db") return "db";
  if (m === "local") return "local";
  if (s3Ready && s3PublicBase) return "s3";
  return cfg.isProduction ? "db" : "local";
}

// Detect the real file type from its first bytes. The client-declared MIME type is
// not trusted (Flutter's multipart upload defaults to application/octet-stream).
function sniff(buf) {
  if (!buf || buf.length < 12) return null;
  const head4 = buf.slice(0, 4).toString("latin1");
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return { mime: "image/jpeg", ext: ".jpg", kind: "image" };
  if (buf[0] === 0x89 && head4.slice(1) === "PNG") return { mime: "image/png", ext: ".png", kind: "image" };
  if (head4 === "GIF8") return { mime: "image/gif", ext: ".gif", kind: "image" };
  if (head4 === "RIFF" && buf.slice(8, 12).toString("latin1") === "WEBP") return { mime: "image/webp", ext: ".webp", kind: "image" };
  if (head4 === "%PDF") return { mime: "application/pdf", ext: ".pdf", kind: "file" };
  if (buf[0] === 0x1a && buf[1] === 0x45 && buf[2] === 0xdf && buf[3] === 0xa3) return { mime: "video/webm", ext: ".webm", kind: "video" };
  if (buf.slice(4, 8).toString("latin1") === "ftyp") {
    const brand = buf.slice(8, 12).toString("latin1");
    if (["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].includes(brand)) return { mime: "image/heic", ext: ".heic", kind: "image" };
    if (brand === "avif") return { mime: "image/avif", ext: ".avif", kind: "image" };
    if (brand === "qt  ") return { mime: "video/quicktime", ext: ".mov", kind: "video" };
    if (brand.startsWith("3g")) return { mime: "video/3gpp", ext: ".3gp", kind: "video" };
    if (brand.startsWith("M4A") || brand === "M4B ") return null;
    return { mime: "video/mp4", ext: ".mp4", kind: "video" };
  }
  return null;
}

const MEDIA_TYPE = { image: "IMAGE", video: "VIDEO", file: "FILE" };

/**
 * Store one uploaded file (multer memory file).
 * kinds: which kinds are acceptable for this endpoint.
 * Returns { url, mediaType, mime, size } where url may be relative ("/media/..") and is
 * resolved by clients against the API base URL.
 */
async function storeUpload(file, { kinds = ["image", "video"], ownerId = null } = {}) {
  if (!file || !Buffer.isBuffer(file.buffer) || !file.buffer.length) {
    throw httpError(400, "INVALID_FILE", "ملف الرفع غير صالح");
  }
  const info = sniff(file.buffer);
  if (!info || !kinds.includes(info.kind)) {
    throw httpError(415, "UNSUPPORTED_FILE", "نوع الملف غير مدعوم. استخدم صورة (JPG/PNG/WebP) أو فيديو MP4.");
  }
  const size = file.buffer.length;
  const mode = backend();
  const name = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}${info.ext}`;
  let url;

  if (mode === "s3") {
    const key = `media/${name}`;
    await s3.send(new PutObjectCommand({ Bucket: process.env.S3_BUCKET, Key: key, Body: file.buffer, ContentType: info.mime }));
    url = `${s3PublicBase}/${key}`;
  } else if (mode === "db") {
    if (size > cfg.dbMediaMaxBytes) {
      throw httpError(413, "FILE_TOO_LARGE", "الملف كبير جدًا. اختر ملفًا أصغر أو فعّل تخزين Cloudflare R2.");
    }
    const id = makeId("m");
    await prisma.media.create({ data: { id, mime: info.mime, size, data: file.buffer, ownerId } });
    url = `/media/${id}${info.ext}`;
  } else {
    fs.mkdirSync(uploadDir, { recursive: true });
    fs.writeFileSync(path.join(uploadDir, name), file.buffer);
    url = `/uploads/${name}`;
  }
  return { url, mediaType: MEDIA_TYPE[info.kind], mime: info.mime, size };
}

// GET /media/:file with HTTP Range support (video seeking on mobile).
async function serveMedia(req, res) {
  const id = String(req.params.file || "").split(".")[0];
  const row = id ? await prisma.media.findUnique({ where: { id } }) : null;
  if (!row) return res.status(404).json({ code: "NOT_FOUND", error: "Not found" });
  const data = Buffer.from(row.data);
  const total = data.length;
  res.set({
    "Content-Type": row.mime,
    "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=31536000, immutable",
    "X-Content-Type-Options": "nosniff",
    "Cross-Origin-Resource-Policy": "cross-origin"
  });
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (m) {
      let start = m[1] === "" ? NaN : parseInt(m[1], 10);
      let end = m[2] === "" ? NaN : parseInt(m[2], 10);
      if (Number.isNaN(start)) { start = Math.max(0, total - end); end = total - 1; }
      else if (Number.isNaN(end) || end >= total) end = total - 1;
      if (start > end || start >= total) {
        res.set("Content-Range", `bytes */${total}`);
        return res.status(416).end();
      }
      res.status(206).set({ "Content-Range": `bytes ${start}-${end}/${total}`, "Content-Length": String(end - start + 1) });
      return res.end(data.subarray(start, end + 1));
    }
  }
  res.set("Content-Length", String(total));
  return res.end(data);
}

module.exports = { uploadDir, storeUpload, serveMedia, sniff, backend };
