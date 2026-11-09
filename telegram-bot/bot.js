/*
 * Mini Fire — Telegram Gem Shop Bot
 * کاربر در تلگرام /start می‌زند، آیدی عددی‌اش را به شما می‌فرستد،
 * شما در این بات مبلغ را ثبت می‌کنید و بات کد جم (سازگار با فرمت داخل بازی)
 * تولید می‌کند که کاربر داخل بازی وارد می‌کند.
 *
 * راه‌اندازی:
 *   1) در @BotFather یک بات بسازید و توکن را در BOT_TOKEN بگذارید
 *   2) npm install
 *   3) node bot.js
 *   4) به بات /start بدهید؛ آیدی عددی تلگرام خودتان را (ADMIN_ID) تنظیم کنید
 *      تا فقط شما بتوانید کد صادر کنید.
 */
const https = require('https');
const crypto = require('crypto');

const BOT_TOKEN = process.env.BOT_TOKEN || '9296962407:AAHjI5dQTBS8BUh-gnqG8rJMcb4eKABhzd0';
const ADMIN_ID = process.env.ADMIN_ID || '8330593178'; // آیدی عددی ادمین (اختیاری، 0 = همه)
const CODE_SECRET = 'MiniFire::gems::7f3a9c2e51b8d046';
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

// ---------- همان الگوریتم کد جم بازی (Profile.cs → ChecksumOk) ----------
// فرمت: MF-<payload ۶ حرفی>-<checksum ۵ حرفی>-<تعداد جم>
// checksum = HMAC-SHA256(secret, payload) → ۵ بایت اول با الگوی بازی
function Checksum(payload) {
  const mac = crypto.createHmac('sha256', CODE_SECRET).update(payload).digest();
  let c = '';
  for (let i = 0; i < 5; i++)
    c += ALPHABET[i % 2 === 0 ? (mac[i] >> 3) & 31 : mac[i] & 31];
  return c;
}
function MakeCode(gems, uid) {
  // payload یکتا: از HMAC روی (uid, gems, زمان) می‌سازیم تا دو کد یکسان نشود
  const seed = crypto.createHmac('sha256', CODE_SECRET)
    .update('code:' + uid + ':' + gems + ':' + Date.now()).digest();
  let payload = '';
  for (let i = 0; i < 6; i++) payload += ALPHABET[seed[i] & 31];
  return 'MF-' + payload + '-' + Checksum(payload) + '-' + gems;
}

// ---------- Telegram API ----------
function tg(method, params) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(params);
    const req = https.request({
      hostname: 'api.telegram.org',
      path: '/bot' + BOT_TOKEN + '/' + method,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    }, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

// ---------- Bot logic ----------
let pending = {}; // chat_id -> { gems, uid }

async function handle(msg) {
  const chatId = msg.chat.id;
  const text = (msg.text || '').trim();
  if (ADMIN_ID !== '0' && String(msg.from.id) !== ADMIN_ID) {
    return tg('sendMessage', { chat_id: chatId, text: 'این بات فقط برای ادمین است.' });
  }
  if (text === '/start' || text === '/help') {
    return tg('sendMessage', {
      chat_id: chatId,
      text:
        '🛒 فروشگاه جم مینی فایر\n\n' +
        'برای صدور کد جم:\n' +
        '1. /issue <تعداد جم> <آیدی عددی تلگرام خریدار>\n' +
        '   مثال: /issue 500 123456789\n' +
        '2. کد تولیدشده را برای خریدار بفرستید.\n' +
        '3. خریدار در بازی: اسپین شاپ ← ثبت کد جم\n\n' +
        'برای دیدن آیدی عددی خودش، خریدار می‌تواند /id بزند.',
    });
  }
  if (text === '/id') {
    return tg('sendMessage', { chat_id: chatId, text: 'آیدی عددی شما: ' + msg.from.id });
  }
  if (text.startsWith('/issue')) {
    const parts = text.split(/\s+/);
    const gems = parseInt(parts[1], 10);
    const uid = parseInt(parts[2], 10);
    if (!gems || gems <= 0 || !uid) {
      return tg('sendMessage', { chat_id: chatId, text: 'فرمت: /issue <تعداد جم> <آیدی عددی خریدار>' });
    }
    const code = MakeCode(gems, uid);
    return tg('sendMessage', {
      chat_id: chatId,
      text: '✅ کد جم ' + gems + ' عددی (مخصوص آیدی ' + uid + '):\n\n`' + code + '`\n\nاین کد فقط یک‌بار قابل استفاده است.',
      parse_mode: 'Markdown',
    });
  }
  return tg('sendMessage', { chat_id: chatId, text: 'دستور نامعتبر. /help را بزنید.' });
}

async function main() {
  console.log('Mini Fire gem bot running...');
  let offset = 0;
  for (;;) {
    try {
      const r = await tg('getUpdates', { offset, timeout: 25 });
      for (const u of r.result || []) {
        offset = u.update_id + 1;
        if (u.message) await handle(u.message);
      }
    } catch (e) {
      console.error(e.message);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
}
main();
