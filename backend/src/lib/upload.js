const multer = require("multer");
const cfg = require("./config");

// Accept any multipart file here; the real type is verified from the bytes in storage.storeUpload().
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: cfg.maxUploadBytes, files: 6, fields: 40 }
});

module.exports = upload;
