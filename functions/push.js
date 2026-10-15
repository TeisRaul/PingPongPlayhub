// Trimite notificare push (telefon / browser) pentru fiecare notificare nouă din `notifications`.
//
// Fluxul: aplicația salvează token-ul dispozitivului în `push_tokens/{token}` (uid, platform)
// → la fiecare document nou în `notifications` găsim token-urile destinatarului, compunem textul
// în limba lui din functions/i18n.json și trimitem prin Firebase Cloud Messaging.
//
// Setup: doar `firebase deploy --only functions` (FCM e activ implicit în proiectul Firebase).
//   iOS: în Firebase Console → Project settings → Cloud Messaging încarci cheia APNs (.p8).
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const translations = require("./i18n.json");

// Aceeași regiune ca în email.js (regiunea bazei Firestore).
const REGION = "us-central1";
const FALLBACK_LANG = "ro";
const SITE = "https://pingpongplayhub.web.app";

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

exports.sendPushNotification = onDocumentCreated(
    {document: "notifications/{notifId}", region: REGION},
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const n = snap.data() || {};
      const ref = snap.ref;
      const db = admin.firestore();

      if (n.pushSentAt || n.skipPush === true || !n.toUid) return;
      if (n.status && n.status !== "pending") return;

      try {
        const [userSnap, venueSnap, tokenSnap] = await Promise.all([
          db.collection("users").doc(n.toUid).get(),
          db.collection("venues").doc(n.toUid).get(),
          db.collection("push_tokens").where("uid", "==", n.toUid).get(),
        ]);
        const profile = userSnap.exists ? userSnap.data() : (venueSnap.exists ? venueSnap.data() : {});
        const venue = venueSnap.exists ? venueSnap.data() : {};
        if (profile.pushNotifications === false || venue.pushNotifications === false) return;
        if (tokenSnap.empty) return;

        const requested = profile.language || venue.language || FALLBACK_LANG;
        const lang = translations[requested] ? requested : FALLBACK_LANG;
        const args = n.args || {};
        const title = n.titleKey ? t(lang, n.titleKey, args) : (n.title || "Playhub");
        const body = n.bodyKey ? t(lang, n.bodyKey, args) : (n.body || "");
        if (!title && !body) return;

        const tokens = tokenSnap.docs.map((d) => d.id);
        const response = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {title: title || "Playhub", body},
          data: {notifId: snap.id, type: String(n.type || "")},
          android: {priority: "high"},
          apns: {payload: {aps: {sound: "default"}}},
          webpush: {
            fcmOptions: {link: SITE},
            notification: {icon: SITE + "/icons/Icon-192.png"},
          },
        });

        // Token-urile expirate / dezinstalate se șterg.
        const dead = [];
        response.responses.forEach((r, i) => {
          const code = r.error && r.error.code;
          if (code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token") {
            dead.push(tokens[i]);
          }
        });
        await Promise.all(dead.map((tk) => db.collection("push_tokens").doc(tk).delete()));

        await ref.update({
          pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
          pushSent: response.successCount,
        });
      } catch (e) {
        console.error("sendPushNotification failed", n.toUid, e);
        try {
          await ref.update({pushError: String(e && e.message ? e.message : e).slice(0, 300)});
        } catch (_) { /* ignore */ }
      }
    },
);
