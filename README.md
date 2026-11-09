# Mini Fire — نسخه Unity

بازسازی کامل بازی Mini Fire (که قبلاً با Godot ساخته شده بود) با **Unity 2022.3.76f1** برای اندروید.

## امکانات

- **شلیک و حرکت دو سویچه (dual-stick)** — دقیقاً مثل مینی میلیتیا؛ ژت‌پک، پرش، دوپشو، اسلحه‌اندازی
- **۱۰ اسلحه**: پیستول، SMG، MP5، MP40، رایفل، Woodpecker، شاتگان، SVD، اسنایپر، راکت — همه داخل مچ با پیکاپ (بدون خرید اسلحه، مثل نسخه اصلی)
- **سیستم گام‌لِوِل**: هر اسلحه ۶ لول (تا ۲ برابر دمیج)؛ لول ۶ گلوله‌های آتشین با سوختن ۵ دمیج در هر نیم ثانیه به مدت ۲ ثانیه — از طریق اسپین شاپ
- **۳۰۰ HP** برای همه بازیکن‌ها
- **۲۸ اسکین کاراکتر** + اسکین‌های اسلحه + پاورها (Damage Boost, Speed Boost, Quick Reload, Extra Armor, Faster Jetpack, Regeneration) — همه با اقتصاد دست‌نخورده نسخه اصلی (۴۰۰ MFC یا ۲۰ جم برای اسپین)
- **ورود با گوگل** (انتخاب حساب، بدون کد تایید) + ذخیره ابری پروفایل در Firebase Firestore — حذف بازی = بازیابی اکانت با ورود دوباره گوگل
- **مولتی‌پلیر آنلاین تا ۱۶ نفر در هر روم** — سازنده روم = هاست، P2P روی UDP، انتخاب رنگ تیم (۱۶ رنگ)، کشف روم‌ها در LAN
- **اسپین شاپ**: گردونه با جایزه‌های MFC/جم/گام‌لول/اسکین/پاور
- **فروشگاه جم تلگرام**: بات Node.js با تولید کد جم سازگار با فرمت بازی (`MF-...-...-gems`)
- **ربات (بوت)** برای تمرین آفلاین

## ساخت APK با GitHub Actions

هر پوش روی برنچ `main` به‌صورت خودکار APK می‌سازد (فایل `Builds/MiniFire.apk` در Artifacts و در Release برای تگ‌ها).

### فعال‌سازی لایسنس Unity (فقط یک بار)

1. در GitHub مخزن را باز کنید → تب **Actions** → **Unity manual activation (one-time)** → **Run workflow**
2. از Artifacts فایل `Unity-activation-request` را دانلود کنید (فایل `.alf`)
3. فایل را در [license.unity3d.com/manual](https://license.unity3d.com/manual) آپلود کنید (لاگین Unity رایگان) و فایل `.ulf` را دانلود کنید
4. محتوای فایل `.ulf` را در GitHub → Settings → Secrets and variables → Actions → **New secret** با نام `UNITY_LICENSE` ذخیره کنید

بعد از آن، هر پوش به‌طور خودکار بیلد می‌گیرد.

### بیلد محلی (اختیاری)

```
Unity 2022.3.76f1 → File → Build Settings → Android → Build
```

(یا از منو: `MiniFire/EditorTools` — اسکریپت بیلد CI همان است.)

## راه‌اندازی Firebase (ورود گوگل و ابر)

راهنمای کامل: [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) — خلاصه:

1. در [console.firebase.google.com](https://console.firebase.google.com) پروژه بسازید
2. اپ اندروید با پکیج `com.smn.minifire` اضافه کنید و **فایل google-services.json** را در `Assets/` بگذارید
3. **Authentication → Sign-in method → Google** را فعال کنید
4. **Firestore** را فعال کنید
5. مقادیر فایل `Assets/StreamingAssets/firebase_config.json` را پر کنید (api_key, project_id, app_id, web_client_id)

بدون این تنظیمات بازی کاملاً کار می‌کند؛ فقط ورود گوگل و ابر غیرفعال است.

## مولتی‌پلیر آنلاین

راهنمای کامل: [docs/ONLINE_PLAY.md](docs/ONLINE_PLAY.md) — خلاصه: برای ایران، بهترین راه **هات‌اسپات موبایل** یا **VPN با IP ثابت** است؛ سازنده روم، روم می‌سازد و بقیه با IP او یا کشف خودکار LAN وارد می‌شوند.

## فروشگاه جم تلگرام

راهنما: [telegram-bot/README.md](telegram-bot/README.md)

## ساختار پروژه

```
Assets/Scripts/Core       — تنظیمات بازی (اقتصاد/اسلحه/پاورها)، پروفایل و ذخیره‌سازی
Assets/Scripts/Gameplay   — رندر آواتار، شبیه‌سازی مسابقه، افکت‌ها، نقشه‌ها
Assets/Scripts/Net        — پروتکل UDP و جلسات P2P (هاست/کلاینت/کشف LAN)
Assets/Scripts/UI         — منو، شاپ، اسپین شاپ، اکانت، لابی، HUD مسابقه
Assets/Scripts/Auth       — ورود گوگل + Firestore (پشت #if FIREBASE_SDK)
Assets/Editor             — اسکریپت بیلد CI
Assets/Resources          — اسپرایت‌ها، نقشه‌ها، صداها (تولیدشده با tools/)
telegram-bot/             — بات فروش جم تلگرام
tools/                    — اسکریپت‌های تولید آرت/متا (پایتون)
.github/workflows         — بیلد خودکار APK
```

## نکته مهم درباره تغییر کدها

این پروژه Unity است: تغییر کدها به معنی **بیلد و نصب مجدد APK** است، نه نصب سریع روی نسخه قبلی. هر بار چیزی عوض شود، GitHub Actions خودش APK جدید می‌سازد و کافی است نسخه جدید را نصب کنید (پروفایل و خریدها با ورود گوگل برمی‌گردد).
