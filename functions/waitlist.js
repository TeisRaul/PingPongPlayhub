// Lista de așteptare: când o rezervare se anulează (sau se șterge), jucătorii care așteptau
// un interval care se suprapune primesc notificare (clopoțel, push, email) și ies din listă.
//
// Intrările sunt create de aplicație în `waitlist/{id}` (uid, venueId, sport, date, startHour, endHour).
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// Aceeași regiune ca în email.js (regiunea bazei Firestore).
const REGION = "us-central1";

function fmtHour(h) {
  const n = Number(h);
  if (!Number.isFinite(n)) return "?";
  let hh = Math.floor(n);
  let mm = Math.round((n - hh) * 60);
  if (mm === 60) {
    hh += 1;
    mm = 0;
  }
  return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0");
}

exports.notifyWaitlist = onDocumentWritten(
    {document: "matches/{matchId}", region: REGION},
    async (event) => {
      const before = event.data.before.exists ? event.data.before.data() : null;
      const after = event.data.after.exists ? event.data.after.data() : null;
      if (!before) return;

      const wasActive = before.status !== "cancelled" && before.status !== "completed";
      const nowFree = !after || after.status === "cancelled";
      if (!wasActive || !nowFree) return;
      // Anulare în masă (mentenanță): intervalul e blocat, nu are sens să anunțăm lista de așteptare.
      if (after && after.massCancel === true) return;

      const venueId = before.locationId;
      const date = before.date;
      if (!venueId || !date) return;
      const start = Number(before.startHour);
      const end = Number(before.endHour);
      if (!Number.isFinite(start) || !Number.isFinite(end)) return;

      const db = admin.firestore();
      const snap = await db.collection("waitlist")
          .where("venueId", "==", venueId).where("date", "==", date).get();
      if (snap.empty) return;

      for (const doc of snap.docs) {
        const w = doc.data();
        const ws = Number(w.startHour);
        const we = Number(w.endHour);
        const sameSport = !w.sport || !before.sport || w.sport === before.sport;
        const overlaps = ws < end && start < we;
        // Cel care a anulat nu e anunțat despre propriul loc.
        if (!sameSport || !overlaps || w.uid === before.hostUid) continue;

        await db.collection("notifications").add({
          toUid: w.uid,
          fromUid: "",
          fromUsername: "",
          fromAvatarUrl: "",
          titleKey: "n.waitlist_title",
          bodyKey: "n.waitlist_body",
          args: {
            venue: String(w.venueName || before.locationName || ""),
            date: String(date),
            time: fmtHour(ws) + " - " + fmtHour(we),
          },
          title: "Playhub",
          body: "",
          type: "waitlist_free",
          status: "pending",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        await doc.ref.delete();
      }
    },
);
