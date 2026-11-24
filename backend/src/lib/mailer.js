const cfg = require("./config");

let transport; // undefined = not tried; null = unavailable
function getTransport() {
  if (transport !== undefined) return transport;
  transport = null;
  if (!cfg.smtp.host) return transport;
  try {
    const nodemailer = require("nodemailer");
    transport = nodemailer.createTransport({
      host: cfg.smtp.host,
      port: cfg.smtp.port,
      secure: cfg.smtp.port === 465,
      auth: cfg.smtp.user ? { user: cfg.smtp.user, pass: cfg.smtp.pass } : undefined
    });
  } catch (e) {
    console.warn("[mail] nodemailer unavailable:", e.message);
  }
  return transport;
}

async function sendMail(to, subject, body) {
  const t = getTransport();
  if (!t) {
    console.log(`[mail:not-configured] to=${to} subject="${subject}" -- ${body}`);
    return false;
  }
  await t.sendMail({ from: cfg.smtp.from, to, subject, text: body });
  return true;
}

module.exports = { sendMail };
