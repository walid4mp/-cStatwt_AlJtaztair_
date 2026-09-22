# Audit V1.3

## إصلاحات حرجة
1. Prisma: تصحيح relation name في User.blocks من `blocker` إلى `blocks`، وهو سبب Validation Error في `Block.blocker`.
2. Flutter: منع API base الفارغ الذي كان يحول `/auth/register` إلى URI نسبي ويظهر `No host specified in URI`. يوجد الآن fallback إلى `https://cstatwt-aljtaztair.onrender.com`.
3. Render: `render.yaml` كان يستخدم `npm ci` بدون `package-lock.json`؛ تم تغييره إلى `npm install`.
4. Prisma: تثبيت Prisma و@prisma/client على 6.19.3.
5. Docker/Render: تشغيل `prisma db push --skip-generate` قبل تشغيل API.
6. Health: `/health` يتحقق من اتصال PostgreSQL.

## إصلاحات API
- تطبيع البريد في التسجيل وتسجيل الدخول.
- تحقق من username/email/password.
- التعامل الصحيح مع P2002 كـ 409.
- التحقق من حالات البلاغات.
- التحقق من الرسائل الفارغة والحظر قبل الإرسال.
- إضافة 404/error middleware.
- تحسين CORS عندما لا يكون `*`.
- عدم استخدام `JWT_SECRET` ضعيفًا في production.
- تصحيح روابط R2/S3 عبر `S3_PUBLIC_BASE_URL`.

## إصلاحات Flutter
- API URL fallback للإنتاج حتى عند غياب GitHub Secret.
- GitHub Actions يبني APK وAAB.
- إصلاح حساب `mine` في المحادثة؛ كان يقارن senderId مع JWT كامل بدل userId.

## اختبار Render الحالي
الرابط `https://cstatwt-aljtaztair.onrender.com` كان يعيد 503 عند الفحص، وهذا متوافق مع فشل deploy الحالي؛ بعد رفع هذه النسخة يجب فحص `/health`.
