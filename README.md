# صوت الجزائر | Sawt AlJazair — V1.3

نسخة V1.3 كاملة وموسعة من التطبيق المدني/الاجتماعي الجزائري.

## ما الجديد في V1.3
- واجهة جديدة مستوحاة من هوية الصورة الترويجية: أخضر/أبيض/أحمر، بطاقات زجاجية خفيفة، خرائط، درع ومؤشرات أمان.
- جميع الولايات الجزائرية الـ58 في الاختيار والفلترة.
- منشورات + صور + فيديوهات + إعجاب + حفظ + تعليق + إعادة نشر.
- إنشاء بلاغات متقدمة مع صور/فيديو، موقع، ولاية، حالة البلاغ، وإمكانية الإخفاء عن الملف العام.
- خريطة البلاغات التفاعلية مع علامات ومعلومات مختصرة.
- بحث متقدم في البلاغات حسب النص والولاية والنوع والحالة.
- نظام الأدلة Evidence للبلاغات.
- نظام المفقودات/المعثورات مع مطابقة تقريبية حسب الفئة والولاية.
- طلب توثيق للحسابات + مراجعة للمشرف.
- محادثات كاملة REST + Socket.IO مع حالة القراءة والكتم والحظر والإبلاغ عن المحادثة.
- لوحة إدارة للمشرفين لمراجعة البلاغات وطلبات التوثيق.
- تخزين وسائط S3/R2 اختياري في الإنتاج، مع fallback محلي للتطوير.
- حماية الخصوصية: الإبلاغ المجهول، إخفاء الإحداثيات الدقيقة في العرض العام، وعدم تقديم اتهام كمعلومة مؤكدة.
- GitHub Actions لبناء APK.
- Render Blueprint لـ API + PostgreSQL.

## تشغيل Flutter
```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:4000
```

## تشغيل Backend
```bash
cd backend
npm install
cp .env.example .env
npx prisma generate
npx prisma db push
npm run dev
```

## نشر Backend على Render عبر Docker

يوجد `Dockerfile` في جذر المشروع لأن خدمة Render الحالية تستخدم إعداد Docker. يبني الـ Dockerfile مجلد `backend` ويشغّل `npm start` مع منفذ Render عبر `PORT`.

إذا كانت خدمة Render مضبوطة على Docker، لا تحتاج إلى نقل Dockerfile إلى `backend`. أما `render.yaml` فهو Blueprint اختياري لإنشاء خدمة Node + PostgreSQL جديدة.

## متغيرات الإنتاج
- `DATABASE_URL`
- `JWT_SECRET`
- `CORS_ORIGIN`
- `PORT`
- `PUBLIC_BASE_URL`
- `S3_PUBLIC_BASE_URL` (مطلوب عند استخدام R2/S3 إذا كانت الملفات ستُعرض مباشرة)
- `S3_ENDPOINT` (اختياري لـ Cloudflare R2 أو أي S3-compatible)
- `S3_BUCKET`
- `S3_REGION`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`

إذا لم تُضبط متغيرات S3، يستخدم الخادم مجلد `uploads/` للتطوير فقط.
على Render، التخزين المحلي ليس دائمًا، لذلك يجب استخدام R2/S3 قبل إطلاق نسخة إنتاج.

## ملاحظة مهمة عن البلاغات
البلاغ هو محتوى مقدم من مستخدم ويحتاج مراجعة. التطبيق لا يصف شخصًا بأنه "مجرم" أو "سارق" لمجرد ورود بلاغ بحقه. الحالات الرسمية للمراجعة منفصلة عن ادعاء المستخدم.

## الصورة الترويجية
تم وضع الصورة المطلوبة داخل:
`assets/branding/app_poster.png`
وتظهر في صفحة التعريف/الترحيب داخل التطبيق.

## API
انظر `docs/V1.3.md`.


## إنتاج Render
رابط API الإنتاج الحالي: `https://cstatwt-aljtaztair.onrender.com`

مهم: إذا كانت خدمة Render تعمل عبر Docker فسيستخدم `Dockerfile` الموجود في الجذر. يبدأ الخادم بعد مزامنة Prisma مع قاعدة البيانات (`prisma db push --skip-generate`). يجب أن تكون `DATABASE_URL` و`JWT_SECRET` موجودتين في Render.

إذا كانت خدمة التخزين R2/S3 مفعلة، اضبط `S3_PUBLIC_BASE_URL` على نطاق الملفات العام؛ لا تستخدم رابط S3 الداخلي كعنوان صورة في التطبيق.

## V1.4.5 shared database safety
This version does not execute `prisma db push` at startup. It is intended for a PostgreSQL database shared with another application. See `docs/SHARED_DATABASE_SAFE_MIGRATION.md`.


## V1.4.5.0
Shared PostgreSQL compatibility release. Startup performs only an additive nullable migration and never resets the shared database.
