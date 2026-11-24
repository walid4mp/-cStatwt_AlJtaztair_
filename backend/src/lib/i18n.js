// Server-side texts for notifications, in the recipient's language.
const T = {
  ar: {
    like: (v) => ["إعجاب جديد", `${v.name} أُعجب بمنشورك`],
    comment: (v) => ["تعليق جديد", `${v.name} علّق على منشورك: ${v.text}`],
    follow: (v) => ["متابع جديد", `${v.name} بدأ بمتابعتك`],
    message: (v) => [v.name, v.text],
    report_status: (v) => ["تحديث على بلاغك", `بلاغ «${v.title}»: ${v.status}`],
    verification: (v) => ["طلب التوثيق", v.approved ? "تمت الموافقة على توثيق حسابك ✅" : "تم رفض طلب التوثيق" + (v.note ? `: ${v.note}` : "")],
    new_report: (v) => ["بلاغ جديد للمراجعة", `${v.title} — ${v.wilaya}`],
    new_flag: () => ["إبلاغ جديد عن محتوى", "هناك محتوى بحاجة للمراجعة"],
    new_verification: (v) => ["طلب توثيق جديد", `${v.name} يطلب توثيق حسابه`],
    welcome: (v) => ["مرحبًا بك في صوت الجزائر 🇩🇿", `أهلاً ${v.name}! ابدأ بالإبلاغ والمشاركة وحماية مجتمعك.`],
    banned: () => ["تم تقييد حسابك", "تم تقييد حسابك من قبل الإدارة."],
    lf_match: (v) => ["احتمال تطابق في المفقودات", `قد يكون «${v.title}» مطابقًا لإعلانك`],
    status: { PENDING: "قيد الانتظار", REVIEWED: "قيد المراجعة", VERIFIED: "تم التحقق", RESOLVED: "تمت المعالجة", REJECTED: "مرفوض" }
  },
  fr: {
    like: (v) => ["Nouveau j’aime", `${v.name} a aimé votre publication`],
    comment: (v) => ["Nouveau commentaire", `${v.name} a commenté : ${v.text}`],
    follow: (v) => ["Nouvel abonné", `${v.name} s’est abonné à votre profil`],
    message: (v) => [v.name, v.text],
    report_status: (v) => ["Mise à jour de votre signalement", `« ${v.title} » : ${v.status}`],
    verification: (v) => ["Demande de vérification", v.approved ? "Votre compte a été vérifié ✅" : "Votre demande a été refusée" + (v.note ? ` : ${v.note}` : "")],
    new_report: (v) => ["Nouveau signalement à examiner", `${v.title} — ${v.wilaya}`],
    new_flag: () => ["Nouveau contenu signalé", "Un contenu nécessite une vérification"],
    new_verification: (v) => ["Nouvelle demande de vérification", `${v.name} demande la vérification de son compte`],
    welcome: (v) => ["Bienvenue sur Sawt Aljazair 🇩🇿", `Bonjour ${v.name} ! Signalez, partagez et protégez votre communauté.`],
    banned: () => ["Compte restreint", "Votre compte a été restreint par l’administration."],
    lf_match: (v) => ["Correspondance possible", `« ${v.title} » pourrait correspondre à votre annonce`],
    status: { PENDING: "En attente", REVIEWED: "En cours d’examen", VERIFIED: "Vérifié", RESOLVED: "Traité", REJECTED: "Rejeté" }
  },
  en: {
    like: (v) => ["New like", `${v.name} liked your post`],
    comment: (v) => ["New comment", `${v.name} commented: ${v.text}`],
    follow: (v) => ["New follower", `${v.name} started following you`],
    message: (v) => [v.name, v.text],
    report_status: (v) => ["Update on your report", `“${v.title}”: ${v.status}`],
    verification: (v) => ["Verification request", v.approved ? "Your account has been verified ✅" : "Your verification request was declined" + (v.note ? `: ${v.note}` : "")],
    new_report: (v) => ["New report to review", `${v.title} — ${v.wilaya}`],
    new_flag: () => ["New flagged content", "A piece of content needs review"],
    new_verification: (v) => ["New verification request", `${v.name} requested account verification`],
    welcome: (v) => ["Welcome to Sawt Aljazair 🇩🇿", `Hi ${v.name}! Report, share and protect your community.`],
    banned: () => ["Account restricted", "Your account has been restricted by the administration."],
    lf_match: (v) => ["Possible match found", `“${v.title}” may match your listing`],
    status: { PENDING: "Pending", REVIEWED: "Under review", VERIFIED: "Verified", RESOLVED: "Resolved", REJECTED: "Rejected" }
  }
};

function pick(lang) { return T[lang] || T.ar; }

function text(lang, type, vars = {}) {
  const t = pick(lang);
  const fn = t[type];
  if (typeof fn !== "function") return [type, ""];
  return fn(vars);
}

function statusLabel(lang, status) {
  return pick(lang).status[status] || status;
}

module.exports = { text, statusLabel };
