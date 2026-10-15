// Trimite pe email fiecare notificare nouă din colecția `notifications`.
//
// Fluxul: aplicația scrie un document în `notifications` (vezi lib/services/notification_service.dart)
// → această funcție îl citește, găsește emailul contului destinatarului și limba lui,
// compune mesajul din cheile de traducere (functions/i18n.json) și îl trimite prin SMTP.
//
// Setup (o singură dată):
//   firebase functions:secrets:set SMTP_URL
//     ex. Gmail cu parolă de aplicație:  smtps://adresa%40gmail.com:PAROLA_DE_APLICATIE@smtp.gmail.com:465
//     ex. alt furnizor (Brevo, Mailgun, SendGrid SMTP...): smtps://utilizator:parola@gazda:465
//   (caracterele speciale din utilizator/parolă se scriu URL-encoded, ex. @ = %40)
//   cd functions && npm install
//   firebase deploy --only functions
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret, defineString} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

const translations = require("./i18n.json");

const SMTP_URL = defineSecret("SMTP_URL");
// Expeditorul afișat în email. Dacă rămâne gol, se folosește utilizatorul din SMTP_URL.
const MAIL_FROM = defineString("MAIL_FROM", {default: ""});

// IMPORTANT: regiunea trebuie să fie cea a bazei Firestore (Firebase Console → Firestore → Locație).
// nam5 / us-central → "us-central1";  eur3 → "europe-west1".
const REGION = "us-central1";

const FALLBACK_LANG = "ro";

// Tipurile care așteaptă un răspuns (Acceptă/Refuză) în aplicație.
const ACTIONABLE = new Set(["join_request", "trainer_request"]);

function t(lang, key, args) {
  const dict = translations[lang] || translations[FALLBACK_LANG];
  let text = dict[key] || (translations.en_US && translations.en_US[key]) ||
    translations[FALLBACK_LANG][key];
  if (text === undefined) return "";
  Object.keys(args || {}).forEach((name) => {
    text = text.split("{" + name + "}").join(String(args[name]));
  });
  return text;
}

function esc(s) {
  return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
}

async function loadRecipient(uid) {
  const db = admin.firestore();
  const [userSnap, venueSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("venues").doc(uid).get(),
  ]);
  const profile = userSnap.exists ? userSnap.data() : (venueSnap.exists ? venueSnap.data() : {});
  const venue = venueSnap.exists ? venueSnap.data() : {};

  // Emailul "atașat contului" = cel din Firebase Auth; documentul e doar rezervă.
  let email = "";
  try {
    email = (await admin.auth().getUser(uid)).email || "";
  } catch (e) {
    email = "";
  }
  if (!email) email = profile.email || venue.email || "";

  const lang = profile.language || venue.language || FALLBACK_LANG;
  const optOut = profile.emailNotifications === false || venue.emailNotifications === false;
  const name = profile.firstName || profile.name || venue.name || "";
  return {email, lang: translations[lang] ? lang : FALLBACK_LANG, optOut, name};
}

function render(lang, n, name) {
  const args = n.args || {};
  const title = n.titleKey ? t(lang, n.titleKey, args) : (n.title || "Playhub");
  const body = n.bodyKey ? t(lang, n.bodyKey, args) : (n.body || "");
  const hint = ACTIONABLE.has(n.type) ? t(lang, "email.action_hint") : "";
  const greeting = t(lang, "email.greeting");
  const footer = t(lang, "email.footer");

  const text = [greeting, "", title, body, hint ? "" : null, hint || null, "", "— Playhub", footer]
      .filter((l) => l !== null).join("\n");

  const html = `<!doctype html><html><body style="margin:0;background:#f4f6f8;font-family:Arial,Helvetica,sans-serif;">
<div style="max-width:520px;margin:24px auto;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e3e7ea;">
  <div style="background:#0d2b45;color:#ffffff;padding:16px 24px;font-size:20px;font-weight:bold;">Playhub</div>
  <div style="padding:24px;color:#1b2a35;">
    <p style="margin:0 0 12px;color:#5b6b76;">${esc(greeting)}${name ? " " + esc(name) : ""}</p>
    <h2 style="margin:0 0 12px;font-size:18px;">${esc(title)}</h2>
    <p style="margin:0 0 16px;font-size:15px;line-height:1.5;white-space:pre-line;">${esc(body)}</p>
    ${hint ? `<p style="margin:0 0 16px;padding:12px;background:#fff6e0;border-radius:8px;font-size:14px;">${esc(hint)}</p>` : ""}
  </div>
  <div style="padding:14px 24px;background:#f4f6f8;color:#7b8a94;font-size:12px;">${esc(footer)}</div>
</div></body></html>`;
  return {subject: title, text, html};
}

exports.sendNotificationEmail = onDocumentCreated(
    {document: "notifications/{notifId}", region: REGION, secrets: [SMTP_URL]},
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const n = snap.data() || {};
      const ref = snap.ref;

      if (n.emailSentAt || n.skipEmail === true) return;
      if (!n.toUid) return;
      if (n.status && n.status !== "pending") return;

      try {
        const rcpt = await loadRecipient(n.toUid);
        if (!rcpt.email) {
          await ref.update({emailError: "no-email"});
          return;
        }
        if (rcpt.optOut) {
          await ref.update({emailError: "opted-out"});
          return;
        }

        const mail = render(rcpt.lang, n, rcpt.name);
        const url = SMTP_URL.value();
        const transport = nodemailer.createTransport(url);
        let from = MAIL_FROM.value();
        if (!from) {
          try {
            from = "Playhub <" + decodeURIComponent(new URL(url).username) + ">";
          } catch (e) {
            from = "Playhub";
          }
        }
        await transport.sendMail({from, to: rcpt.email, subject: mail.subject, text: mail.text, html: mail.html});
        await ref.update({emailSentAt: admin.firestore.FieldValue.serverTimestamp(), emailLang: rcpt.lang});
      } catch (e) {
        // Nu aruncăm eroarea mai departe (ar reîncerca la nesfârșit); o păstrăm pe document.
        console.error("sendNotificationEmail failed", n.toUid, e);
        try {
          await ref.update({emailError: String(e && e.message ? e.message : e).slice(0, 300)});
        } catch (_) { /* ignore */ }
      }
    },
);
