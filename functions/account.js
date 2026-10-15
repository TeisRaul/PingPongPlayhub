// Export de date și ștergere de cont (GDPR / cerințe Google Play și App Store).
//
// - exportMyData:    întoarce un JSON cu tot ce știm despre utilizatorul autentificat.
// - deleteMyAccount: șterge contul și datele personale; păstrează, anonimizate, meciurile
//                    încheiate (istoric pentru ceilalți jucători și evidență financiară).
//
// Deploy: firebase deploy --only functions
const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const DELETED_NAME = "Deleted user";

async function authenticate(req, res) {
  const header = req.get("Authorization") || "";
  const match = header.match(/^Bearer (.+)$/);
  if (!match) {
    res.status(401).json({error: "Missing auth token"});
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch (e) {
    res.status(401).json({error: "Invalid auth token"});
    return null;
  }
}

// Timestamp / GeoPoint / DocumentReference -> valori simple, ca să încapă în JSON.
function plain(v) {
  if (v === null || v === undefined) return v;
  if (v instanceof admin.firestore.Timestamp) return v.toDate().toISOString();
  if (v instanceof admin.firestore.GeoPoint) return {lat: v.latitude, lng: v.longitude};
  if (v instanceof admin.firestore.DocumentReference) return v.path;
  if (Array.isArray(v)) return v.map(plain);
  if (typeof v === "object") {
    const o = {};
    Object.keys(v).forEach((k) => {
      o[k] = plain(v[k]);
    });
    return o;
  }
  return v;
}

function docs(snap) {
  return snap.docs.map((d) => ({id: d.id, ...plain(d.data())}));
}

async function safe(promise) {
  try {
    return await promise;
  } catch (e) {
    console.error("export query failed", e.message);
    return null;
  }
}

exports.exportMyData = onRequest({cors: true, timeoutSeconds: 120}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  const uid = decoded.uid;
  const db = admin.firestore();

  try {
    const [userSnap, venueSnap] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("venues").doc(uid).get(),
    ]);
    const out = {
      exportedAt: new Date().toISOString(),
      uid,
      email: decoded.email || null,
      profile: userSnap.exists ? plain(userSnap.data()) : null,
      venue: venueSnap.exists ? plain(venueSnap.data()) : null,
    };

    const sub = async (path) => {
      const s = await safe(db.collection(path).get());
      return s ? docs(s) : [];
    };
    out.subscriptions = await sub(`users/${uid}/subscriptions`);
    out.reviewsAboutMe = await sub(`users/${uid}/reviews`);

    const q = async (col, field, op = "==") => {
      const s = await safe(db.collection(col).where(field, op, uid).limit(1000).get());
      return s ? docs(s) : [];
    };
    out.matchesHosted = await q("matches", "hostUid");
    out.matchesJoined = await q("matches", "joinedUids", "array-contains");
    out.trainerSessionsAsClient = await q("reservations", "creatorId");
    out.trainerSessionsAsTrainer = await q("reservations", "trainerId");
    out.notifications = await q("notifications", "toUid");
    out.friendRequestsSent = await q("friend_requests", "fromUid");
    out.friendRequestsReceived = await q("friend_requests", "toUid");
    out.friendships = await q("friendships", "uids", "array-contains");
    out.posts = await q("posts", "authorUid");
    out.tournaments = await q("tournaments", "joinedUids", "array-contains");

    // Conversații: doar mesajele trimise de utilizator.
    const chats = await q("chats", "uids", "array-contains");
    out.messagesSent = [];
    for (const c of chats) {
      const ms = await safe(db.collection("chats").doc(c.id).collection("messages")
          .where("senderUid", "==", uid).limit(2000).get());
      if (ms) out.messagesSent.push({chatId: c.id, messages: docs(ms)});
    }

    res.status(200).json(out);
  } catch (error) {
    console.error("exportMyData error:", error);
    res.status(500).json({error: "Could not export data"});
  }
});

async function deleteWhere(db, col, field, op, value) {
  const snap = await db.collection(col).where(field, op, value).get();
  const writer = db.bulkWriter();
  snap.docs.forEach((d) => writer.delete(d.ref));
  await writer.close();
  return snap.size;
}

exports.deleteMyAccount = onRequest(
    {cors: true, timeoutSeconds: 300, secrets: [STRIPE_SECRET_KEY]},
    async (req, res) => {
      if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
      const decoded = await authenticate(req, res);
      if (!decoded) return;
      if (!req.body || req.body.confirm !== true) {
        return res.status(400).json({error: "Missing confirmation"});
      }
      const uid = decoded.uid;
      const db = admin.firestore();

      try {
        const userRef = db.collection("users").doc(uid);
        const venueRef = db.collection("venues").doc(uid);
        const [userSnap, venueSnap] = await Promise.all([userRef.get(), venueRef.get()]);
        const user = userSnap.exists ? userSnap.data() : {};
        const venue = venueSnap.exists ? venueSnap.data() : {};

        // Conturile de administrator nu se șterg din aplicație.
        if (user.isAdmin === true || user.role === "admin") {
          return res.status(403).json({error: "Admin accounts cannot be deleted here"});
        }

        // 1) Abonamentul Stripe al sălii (altfel ar continua să fie taxat).
        const subId = venue.billing && venue.billing.stripeSubscriptionId;
        if (subId) {
          try {
            await require("stripe")(STRIPE_SECRET_KEY.value()).subscriptions.cancel(subId);
          } catch (e) {
            console.error("Could not cancel subscription", subId, e.message);
          }
        }

        // 2) Meciuri la care participă: iese din ele; încheiate/anulate -> doar anonimizat.
        const joined = await db.collection("matches").where("joinedUids", "array-contains", uid).get();
        const hosted = await db.collection("matches").where("hostUid", "==", uid).get();
        const seen = new Set();
        const matchDocs = [...joined.docs, ...hosted.docs].filter((d) => {
          if (seen.has(d.id)) return false;
          seen.add(d.id);
          return true;
        });
        const writer = db.bulkWriter();
        for (const d of matchDocs) {
          const m = d.data();
          const finished = m.status === "completed" || m.status === "cancelled";
          const players = Array.isArray(m.joinedPlayers) ? m.joinedPlayers : [];
          if (finished) {
            const anon = players.map((p) => (p && p.uid === uid ?
              {...p, username: DELETED_NAME, avatarUrl: "", name: DELETED_NAME} : p));
            const upd = {joinedPlayers: anon};
            if (m.hostUid === uid) {
              upd.hostUsername = DELETED_NAME;
              upd.hostAvatarUrl = "";
            }
            writer.update(d.ref, upd);
            continue;
          }
          const rest = players.filter((p) => !(p && p.uid === uid));
          const restUids = (m.joinedUids || []).filter((x) => x !== uid);
          if (m.hostUid === uid && rest.length === 0) {
            writer.update(d.ref, {
              status: "cancelled", cancelReason: "account_deleted",
              joinedPlayers: [], joinedUids: [],
            });
          } else if (m.hostUid === uid) {
            const newHost = {...rest[0], role: "host"};
            rest[0] = newHost;
            writer.update(d.ref, {
              joinedPlayers: rest, joinedUids: restUids, status: "open",
              hostUid: newHost.uid || restUids[0] || "",
              hostUsername: newHost.username || "",
              hostAvatarUrl: newHost.avatarUrl || "",
            });
          } else {
            writer.update(d.ref, {joinedPlayers: rest, joinedUids: restUids, status: "open"});
          }
        }

        // Rezervările viitoare ale unei săli se anulează.
        if (venueSnap.exists) {
          const vm = await db.collection("matches").where("locationId", "==", uid).get();
          vm.docs.forEach((d) => {
            const st = d.data().status;
            if (st !== "completed" && st !== "cancelled") {
              writer.update(d.ref, {status: "cancelled", cancelReason: "venue_closed"});
            }
          });
        }
        await writer.close();

        // 3) Turnee în care e înscris.
        const tours = await db.collection("tournaments").where("joinedUids", "array-contains", uid).get();
        const tw = db.bulkWriter();
        tours.docs.forEach((d) => {
          const t = d.data();
          if (t.status === "completed") return;
          tw.update(d.ref, {
            joinedUids: (t.joinedUids || []).filter((x) => x !== uid),
            joinedPlayers: (t.joinedPlayers || []).filter((p) => !(p && p.uid === uid)),
          });
        });
        await tw.close();

        // 4) Sesiuni de antrenor (ca client sau antrenor): se anulează cele în curs.
        for (const field of ["creatorId", "trainerId"]) {
          const rs = await db.collection("reservations").where(field, "==", uid).get();
          const rw = db.bulkWriter();
          rs.docs.forEach((d) => {
            const st = d.data().status;
            if (st === "pending" || st === "accepted" || st === "confirmed") {
              rw.update(d.ref, {status: "cancelled", cancelReason: "account_deleted"});
            }
          });
          await rw.close();
        }

        // 5) Date personale: se șterg.
        await deleteWhere(db, "notifications", "toUid", "==", uid);
        await deleteWhere(db, "friend_requests", "fromUid", "==", uid);
        await deleteWhere(db, "friend_requests", "toUid", "==", uid);
        await deleteWhere(db, "friendships", "uids", "array-contains", uid);
        await deleteWhere(db, "username_lookup", "uid", "==", uid);
        await deleteWhere(db, "phone_lookup", "uid", "==", uid);

        const posts = await db.collection("posts").where("authorUid", "==", uid).get();
        for (const p of posts.docs) await db.recursiveDelete(p.ref);

        // Conversații: private (2 persoane) se șterg; de grup -> doar iese din ele.
        const chats = await db.collection("chats").where("uids", "array-contains", uid).get();
        for (const c of chats.docs) {
          const uids = c.data().uids || [];
          if (uids.length <= 2) await db.recursiveDelete(c.ref);
          else await c.ref.update({uids: uids.filter((x) => x !== uid)});
        }

        if (venueSnap.exists) await db.recursiveDelete(venueRef);
        if (userSnap.exists) await db.recursiveDelete(userRef);

        // 6) Contul de autentificare, la final.
        try {
          await admin.auth().deleteUser(uid);
        } catch (e) {
          if (e.code !== "auth/user-not-found") throw e;
        }

        res.status(200).json({deleted: true});
      } catch (error) {
        console.error("deleteMyAccount error:", error);
        res.status(500).json({error: "Could not delete account"});
      }
    },
);
