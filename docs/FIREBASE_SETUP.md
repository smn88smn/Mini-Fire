# راه‌اندازی Firebase (ورود گوگل + ذخیره ابری)

این راهنما برای فعال‌کردن ورود با گوگل و ذخیره ابری پروفایل است. بدون این تنظیمات هم بازی کامل کار می‌کند؛ فقط این دو قابلیت غیرفعال است.

## ۱) ساخت پروژه Firebase

1. به [console.firebase.google.com](https://console.firebase.google.com) بروید و **Add project** بزنید (مثلاً `minifire`)
2. در تنظیمات پروژه، **Android app** اضافه کنید:
   - Package name: **`com.smn.minifire`**
   - SHA-1 (برای Google Sign-In): `A4:49:46:32:06:32:79:F6:27:D9:B5:28:82:8A:B3:4D:A1:E8:70:2A`
   - این SHA-1 مربوط به کی‌استور امضای APK است که در `Assets/Plugins/Android/minifire.keystore` قرار دارد و GitHub Actions با همان امضا می‌کند.
3. فایل **google-services.json** را دانلود کنید و در پوشه `Assets/` پروژه بگذارید.

## ۲) فعال‌کردن ورود با گوگل

1. **Build → Authentication → Get started**
2. در تب **Sign-in method**، **Google** را فعال کنید (Enable)
3. ایمیل پشتیبانی را انتخاب کنید و ذخیره کنید

## ۳) فعال‌کردن Firestore (ذخیره ابری)

1. **Build → Firestore Database → Create database**
2. حالت **Start in test mode** را انتخاب کنید (بعداً قواعد امنیتی بگذارید)
3. برای سادگی، این قواعد را در تب **Rules** بگذارید:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /profiles/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

(هر کاربر فقط پروفایل خودش را می‌خواند/می‌نویسد.)

## ۴) پرکردن تنظیمات داخل بازی

فایل `Assets/StreamingAssets/firebase_config.json` را با مقادیر پروژه خودتان پر کنید:

| فیلد | از کجا |
|---|---|
| `api_key` | Firebase Console → Project settings → General → Web API Key (اگر ندارد: Add app → Web و بعد Google services → API key) |
| `project_id` | Project settings → Project ID |
| `app_id` | Project settings → General → Your apps → Android app → App ID (`1:...:android:...`) |
| `web_client_id` | Project settings → General → Your apps → Web app (اگر Web app ندارید یکی بسازید) → OAuth 2.0 Client ID — برای گوگل‌ساین‌این اندروید لازم است |

مثال:

```json
{
  "api_key": "AIzaSy...",
  "project_id": "minifire-xxxxx",
  "app_id": "1:123456789012:android:abcdef123456",
  "web_client_id": "123456789012-xxxxxxxx.apps.googleusercontent.com"
}
```

## ۵) بیلد

بقیه‌اش خودکار است — GitHub Actions پکیج‌های Firebase (Auth, Firestore) و پلاگین Google Sign-In را دانلود و ایمپورت می‌کند و `FIREBASE_SDK` را فعال می‌سازد. فقط پوش کنید تا APK جدید ساخته شود.

## تست

بعد از نصب APK: منوی اکانت → **Sign in with Google** → پنجره انتخاب حساب گوگل باز می‌شود. بعد از ورود، دکمه **Save to Cloud** / بارگیری ابر فعال می‌شود. اگر بازی را حذف و دوباره نصب کنید و با همان حساب گوگل وارد شوید، پروفایل (سکه، جم، اسکین‌ها، لول‌ها) برمی‌گردد.
