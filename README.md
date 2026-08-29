# تطبيق إدارة الوردية الثانية

تطبيق Flutter عربي RTL لإدارة ومتابعة الوردية الثانية في المصنع، مع نسخة Web متجاوبة تعمل على اللابتوب والموبايل.

## التشغيل على اللابتوب

```powershell
flutter pub get
flutter run -d chrome
```

## فتح التطبيق من الموبايل على نفس شبكة Wi-Fi

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5520
```

بعد التشغيل افتح من الموبايل:

```text
http://IP-اللابتوب:5520
```

لمعرفة IP اللابتوب في Windows:

```powershell
ipconfig
```

## نسخة Release للويب

```powershell
flutter build web --release
```

الملفات الجاهزة تكون داخل `build/web`.

## تشغيل الـ Backend المحلي

من مجلد `backend`:

```powershell
npm install
npm start
```

يعمل الـ API على `http://127.0.0.1:5521`، وتظل البيانات محفوظة في `backend/data/wardia.json`.

لتشغيل الواجهة والـ API معًا، اترك الـ Backend يعمل ثم شغّل Flutter Web على المنفذ `5530`.

## الدخول التجريبي

- البريد: `manager@wardia.app`
- كلمة المرور: `123456`
- مدير النظام: `admin@wardia.app`
- كلمة مرور مدير النظام: `Admin@123456`

## الوضع الحالي

الواجهة الحالية متصلة بالـ Backend المحلي وتستخدم تخزين JSON دائمًا عند عدم ضبط `DATABASE_URL`. تم تنفيذ المرحلة الأولى من وحدة الحضور والغياب بسجلات موظفين تفصيلية، فلاتر، نسب محسوبة تلقائيًا، وتسجيل تعديلات السجلات في سجل الأحداث. باقي الوحدات التشغيلية الحالية محفوظة ولم تتغير.

## ملاحظة بخصوص APK

إخراج Android APK يحتاج Android Studio وAndroid SDK. بيئة البناء الحالية تحتوي Flutter والويب، لكن Android SDK غير مثبت حتى الآن.

## النشر وقاعدة البيانات

ملف `DEPLOYMENT.md` يشرح تشغيل PostgreSQL والـ API ونسخة الويب عبر Docker، وتجهيز HTTPS خلف Nginx أو خدمة استضافة.
