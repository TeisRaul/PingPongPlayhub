// Remindere înainte de meci, configurabile de fiecare jucător.
//
// Fiecare jucător alege (în setările contului, iar pentru un meci anume și separat):
//   - cu cât timp înainte primește prima notificare (1h, 2h, 3h, 1 zi, 2 zile, 3 zile, 1 săptămână);
//   - dacă se repetă (la 30 min, 1h, 2h, 6h, zilnic) și de câte ori sau până începe meciul.
// Setările generale stau în users/{uid}.reminderPrefs, cele pentru un meci în
// match_reminders/{matchId}_{uid} (au prioritate). Ce s-a trimis deja se ține în
// reminder_state/{matchId}_{uid} (doar funcția are acces).
//
// Funcția rulează la 5 minute (Cloud Scheduler → necesită planul Blaze) și creează documente în
// `notifications`; de acolo pleacă în clopoțel, popup și push (sendNotificationEmail le sare,
// ca să nu primești un email la fiecare repetare).
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const translations = require("./i18n.json");

const REGION = "us-central1";
const FALLBACK_LANG = "ro";
const TZ = "Europe/Bucharest"; // orele din rezervări sunt ora locală a sălii
const WINDOW_DAYS = 8; // cea mai lungă setare e 7 zile
const GRACE_MS = 30 * 60 * 1000; // un reminder ratat cu mai mult de 30 min nu se mai trimite
const MAX_TIMES = 20;
const MIN_BEFORE_START_MIN = 10; // repetările nu se trimit cu mai puțin de 10 min înainte de meci

const DEFAULTS = {enabled: true, firstMin: 60, repeatEveryMin: 0, repeatMode: "count", repeatCount: 1};
const FIRST_OPTIONS = [60, 120, 180, 1440, 2880, 4320, 10080];
const REPEAT_OPTIONS = [0, 30, 60, 120, 360, 1440];

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

function tzOffsetMs(utcMs) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TZ, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(new Date(utcMs));
  const g = (type) => Number(parts.find((p) => p.type === type).value);
  const asUtc = Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"), g("second"));
  return asUtc - Math.floor(utcMs / 1000) * 1000;
}

// "2026-10-20" + 18.5 → momentul real (ms UTC) în care începe meciul, ora României.
function startMs(dateStr, hour) {
  const [y, m, d] = String(dateStr).split("-").map(Number);
  if (!y || !m || !d || typeof hour !== "number") return null;
  const h = Math.floor(hour);
  const min = Math.round((hour - h) * 60);
  const guess = Date.UTC(y, m - 1, d, h, min);
  const off1 = tzOffsetMs(guess);
  let ms = guess - off1;
  const off2 = tzOffsetMs(ms);
  if (off2 !== off1) ms = guess - off2;
  return ms;
}

function dayString(ms) {
  return new Intl.DateTimeFormat("en-CA", {timeZone: TZ}).format(new Date(ms)); // yyyy-MM-dd
}

function normalize(raw) {
  const c = Object.assign({}, DEFAULTS, raw && typeof raw === "object" ? raw : {});
  c.enabled = c.enabled !== false;
  if (!FIRST_OPTIONS.includes(c.firstMin)) c.firstMin = DEFAULTS.firstMin;
  if (!REPEAT_OPTIONS.includes(c.repeatEveryMin)) c.repeatEveryMin = 0;
  c.repeatMode = c.repeatMode === "until_start" ? "until_start" : "count";
  c.repeatCount = Math.min(Math.max(parseInt(c.repeatCount, 10) || 0, 0), 10);
  return c;
}

// Momentele (ms) la care trebuie trimis câte un reminder, în ordine.
function fireTimes(start, cfg) {
  const times = [start - cfg.firstMin * 60000];
  if (cfg.repeatEveryMin > 0) {
    const step = cfg.repeatEveryMin * 60000;
    const limit = start - MIN_BEFORE_START_MIN * 60000;
    const extra = cfg.repeatMode === "count" ? cfg.repeatCount : MAX_TIMES;
    for (let k = 1; k <= extra && times.length < MAX_TIMES; k++) {
      const next = times[0] + k * step;
      if (next > limit) break;
      times.push(next);
    }
  }
  return times;
}

function whenText(lang, msLeft) {
  const min = Math.max(Math.round(msLeft / 60000), 1);
  if (min < 90) return t(lang, "n.rem_min", {n: min});
  const hours = Math.round(min / 60);
  if (hours < 20) return t(lang, "n.rem_h", {n: hours});
  const days = Math.max(Math.round(hours / 24), 1);
  return t(lang, days === 1 ? "n.rem_d1" : "n.rem_dn", {n: days});
}

function hourLabel(h) {
  if (typeof h !== "number") return "-";
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0");
}

async function getAllChunked(db, refs) {
  const out = [];
  for (let i = 0; i < refs.length; i += 300) {
    out.push(...await db.getAll(...refs.slice(i, i + 300)));
  }
  return out;
}

exports.sendMatchReminders = onSchedule(
    {schedule: "every 5 minutes", region: REGION, timeZone: TZ, timeoutSeconds: 120},
    async () => {
      const db = admin.firestore();
      const now = Date.now();
      const from = dayString(now - 24 * 3600000);
      const to = dayString(now + WINDOW_DAYS * 24 * 3600000);

      const snap = await db.collection("matches")
          .where("date", ">=", from).where("date", "<=", to).get();

      // (meci, jucător) pentru toți participanții meciurilor viitoare, necanceled.
      const pairs = [];
      snap.forEach((doc) => {
        const m = doc.data();
        if (["cancelled", "completed", "no_show"].includes(m.status)) return;
        const start = startMs(m.date, Number(m.startHour));
        if (start === null || start <= now) return;
        const uids = new Set((Array.isArray(m.joinedUids) ? m.joinedUids : [])
            .filter((u) => typeof u === "string" && u));
        if (m.hostUid) uids.add(m.hostUid);
        uids.forEach((uid) => pairs.push({matchId: doc.id, m, uid, start}));
      });
      if (pairs.length === 0) return;

      const userRefs = [...new Set(pairs.map((p) => p.uid))].map((u) => db.collection("users").doc(u));
      const [userDocs, overrideDocs, stateDocs] = await Promise.all([
        getAllChunked(db, userRefs),
        getAllChunked(db, pairs.map((p) => db.collection("match_reminders").doc(p.matchId + "_" + p.uid))),
        getAllChunked(db, pairs.map((p) => db.collection("reminder_state").doc(p.matchId + "_" + p.uid))),
      ]);
      const users = {};
      userDocs.forEach((d) => {
        if (d.exists) users[d.id] = d.data();
      });

      let sent = 0;
      for (let i = 0; i < pairs.length; i++) {
        const {matchId, m, uid, start} = pairs[i];
        const profile = users[uid];
        if (!profile) continue; // conturi de sală / șterse
        const override = overrideDocs[i].exists ? overrideDocs[i].data() : null;
        const cfg = normalize(override || profile.reminderPrefs);
        if (!cfg.enabled) continue;

        const times = fireTimes(start, cfg);
        const due = times.filter((x) => x <= now).length;
        const state = stateDocs[i].exists ? stateDocs[i].data() : {};
        const already = Number(state.sent) || 0;
        if (due === 0 || due <= already) continue;

        const stateRef = db.collection("reminder_state").doc(matchId + "_" + uid);
        const stale = now - times[due - 1] > GRACE_MS;
        try {
          if (!stale) {
            const lang = translations[profile.language] ? profile.language : FALLBACK_LANG;
            await db.collection("notifications").add({
              toUid: uid,
              fromUid: "",
              fromUsername: "",
              fromAvatarUrl: "",
              titleKey: "n.reminder_title",
              bodyKey: "n.reminder_body",
              args: {
                date: String(m.date || "-"),
                time: hourLabel(Number(m.startHour)) + " - " + hourLabel(Number(m.endHour)),
                venue: String(m.locationName || "-"),
                table: String(m.tableId || "-"),
                when: whenText(lang, start - now),
              },
              title: "Playhub",
              body: "",
              type: "match_reminder",
              status: "pending",
              matchId,
              skipEmail: true,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
            sent++;
          }
          await stateRef.set({
            matchId, uid, sent: due, startMs: start,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        } catch (e) {
          console.error("reminder failed", matchId, uid, e);
        }
      }
      console.log("match reminders: " + sent + " trimise din " + pairs.length + " (meci, jucător)");
    },
);

// Doar pentru teste automate (functions/test/reminders.test.js).
exports._test = {normalize, fireTimes, startMs, whenText, DEFAULTS};
