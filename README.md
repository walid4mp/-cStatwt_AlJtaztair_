# صوت الجزائر | Voix d'Algérie | Sawt Aljazair — v2.0.0

تطبيق مدني اجتماعي: بلاغات + منشورات + خريطة حقيقية + محادثات لحظية + مفقودات + إشعارات + نظام إدارة كامل.
Flutter (Android) + Node/Express/Prisma/PostgreSQL. اللغات: العربية (RTL) / Français / English.

## ما الجديد في 2.0.0
- **إصلاح رفع الصور والفيديو**: الجذر كان أن Flutter يرسل `application/octet-stream`؛ الآن العميل يحدد النوع والخادم يتحقق من محتوى الملف (magic bytes). التخزين: `STORAGE_MODE=db` (افتراضي، يعمل بلا إعداد إضافي)، أو `s3` (Cloudflare R2)، أو `local`.
- **المحادثات**: بدء محادثة من ملف أي مستخدم، صور/فيديو، مؤشر الكتابة، إيصالات القراءة، كتم/حظر/إبلاغ، حذف رسالة، دفع لحظي Socket.IO.
- **الملف الشخصي**: تعديل الصورة والاسم والنبذة والولاية والهاتف/واتساب، متابعة، صفحة مستخدم، بحث أشخاص، تغيير كلمة المرور، حذف الحساب.
- **خريطة حقيقية**: OpenStreetMap + قمر صناعي + تضاريس، تجميع العلامات، فلاتر، بحث أماكن، موقعي، اختيار موقع بالدبوس، فتح في تطبيق الخرائط، إحداثيات تقريبية للعامة.
- **الإشعارات**: داخل التطبيق + نظام (قناة Android أصلية) + Socket.IO + FCM اختياري، وفتح الشاشة المناسبة عند الضغط.
- **الإدارة**: داخل التطبيق (مركز الإدارة) **ولوحة ويب** على `/panel`: مؤشرات، بلاغات (تغيير حالة + ملاحظة + CSV)، مستخدمون (حظر/توثيق/صلاحيات/إعادة كلمة مرور/حذف)، توثيق، شكاوى المحتوى، إخفاء منشورات، بث إشعارات (الكل/ولاية/مستخدم/الإدارة)، إعدادات النظام (صيانة، مراجعة البلاغات قبل النشر، فتح التسجيل، إعلان علوي، أدنى إصدار)، سجل العمليات.
- استعادة كلمة المرور برمز عبر البريد (SMTP).

## إعداد المدير الأول (على Render → Environment)
- `ADMIN_EMAILS=you@example.com` يرفع هذا الحساب (بعد تسجيله) إلى ADMIN عند تشغيل الخادم، **أو**
- `ADMIN_SEED_EMAIL` + `ADMIN_SEED_PASSWORD` لإنشاء مدير تلقائيًا.
ثم افتح `https://<your-api>/panel`.

## متغيرات البيئة المهمة
`DATABASE_URL`, `JWT_SECRET`, `DEDICATED_DATABASE=true` (لتشغيل `prisma db push` تلقائيًا), `STORAGE_MODE=db|s3|local`,
`S3_*` (عند s3), `SMTP_HOST/PORT/USER/PASS/FROM` (استعادة كلمة المرور), `ADMIN_EMAILS`, `ADMIN_SEED_*`.
راجع `backend/.env.example`.

## التشغيل
```bash
# Backend
cd backend && cp .env.example .env && npm install && npx prisma db push && npm start
# Flutter
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:4000
```
البناء عبر GitHub Actions (`.github/workflows/flutter.yml`) ينتج APK و AAB.

## إشعارات الدفع والتطبيق مغلق (FCM) — اختياري
تعمل الإشعارات اللحظية والنظامية والتطبيق مفتوح/في الخلفية القريبة. للدفع والتطبيق مغلق تمامًا: أنشئ مشروع Firebase، أضف `FIREBASE_SERVICE_ACCOUNT` (JSON) للخادم و`npm i firebase-admin`، وأضف `google-services.json` وحزمة `firebase_messaging` للتطبيق. الخادم جاهز (`/me/devices`).

## ملاحظة صريحة عن التحقق
بيئة العمل لم تتضمن Flutter SDK ولا شبكة، لذلك: الخادم فُحص بـ `node --check`/ESLint ومحمّل تجريبي، ولوحة الويب اختُبرت بـ Playwright مع خادم وهمي، أما كود Flutter فمراجَع يدويًا ولم يُترجَم (compile). شغّل `flutter analyze` أولًا؛ أي خطأ نادر سيظهر هناك مباشرة (CI مضبوط بـ `--no-fatal-infos`).
