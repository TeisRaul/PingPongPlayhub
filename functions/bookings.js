// Plata cu cardul a rezervărilor și a abonamentelor de sală, confirmată și rambursată pe server.
//
// Rezervare plătită cu cardul:
//  1. Aplicația creează rezervarea cu paymentStatus = "awaiting_payment" (masa e ținută ocupată).
//  2. createBookingCheckout / createStripePaymentIntent primesc matchId și îl pun în metadata plății.
//  3. Când Stripe confirmă plata (webhook), confirmPayment marchează rezervarea "confirmed" și o
//     trece în registrul cardPayments — chiar dacă aplicația s-a închis între timp.
//  4. Dacă rezervarea nu mai există (expirată / anulată), plata se rambursează automat.
//  5. releaseUnpaidHolds șterge rezervările rămase neplătite și închide plata.
//
// Plata împărțită (paymentMode = "split"):
//  - gazda plătește tot (prețul mesei + taxa platformei), ca sala să fie plătită sigur;
//  - fiecare jucător care se alătură își plătește partea: (preț + taxă) / numărul de locuri;
//  - oricine poate renunța până la începerea meciului și primește înapoi tot ce a plătit;
//  - la ora de început, settleSplitPayments îi rambursează gazdei părțile plătite de ceilalți.
//
// Registrul plăților pe rezervare: cardPayments[uid] = {pi, amount, refunded, role: "host" | "share"}.
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const REGION = "us-central1";
const HOLD_MINUTES = 45; // sesiunea Checkout expiră după 30 de minute; lăsăm o marjă
const PLATFORM_FEE_RON = 5;
const MIN_SHARE_RON = 2; // Stripe nu acceptă plăți mai mici de 2 RON
const SUPER_ADMIN_EMAIL = "teisraul@yahoo.co.uk"; // la fel ca în firestore.rules

function getStripe() {
  return require("stripe")(STRIPE_SECRET_KEY.value());
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const round2 = (x) => Math.round(Number(x) * 100) / 100;
const toBani = (ron) => Math.round(Number(ron) * 100);

function startMs(m) {
  return require("./reminders")._test.startMs(m.date, Number(m.startHour));
}

function hasStarted(m, now = Date.now()) {
  const s = startMs(m);
  return s !== null && s <= now;
}

const isCardMethod = (m) => String(m.paymentMethod || "").includes("Card");

/** Partea fiecărui jucător la plata împărțită: (preț + taxa platformei) / numărul de locuri. */
function shareAmountFor(m) {
  if (typeof m.shareAmount === "number" && m.shareAmount > 0) return round2(m.shareAmount);
  const seats = Number(m.maxPlayers) || 0;
  if (seats < 2) return 0;
  return round2((Number(m.price) + PLATFORM_FEE_RON) / seats);
}

/** Plățile cu cardul ale rezervării; include și rezervările vechi, de dinainte de registru. */
function paymentsOf(m) {
  const out = {...(m.cardPayments || {})};
  if (!out[m.hostUid] && m.stripePaymentIntentId) {
    out[m.hostUid] = {
      pi: m.stripePaymentIntentId,
      amount: Number(m.paidAmount) || Number(m.price) || 0,
      refunded: 0,
      role: "host",
    };
  }
  return out;
}

const remainingOf = (p) => round2(Math.max((Number(p.amount) || 0) - (Number(p.refunded) || 0), 0));

// Validează scopul plății trimis de aplicație. Întoarce metadata pentru Stripe și, unde e cazul,
// suma calculată pe server (care înlocuiește suma trimisă de aplicație).
// purpose = {kind: "booking", matchId} | {kind: "share", matchId} | {kind: "pass", passType, passEntries}
async function purposeMetadata(purpose, uid, venueId) {
  if (!purpose || typeof purpose !== "object") return {meta: {}, amountRon: null};
  const db = admin.firestore();

  if (purpose.kind === "booking" || purpose.kind === "share") {
    const matchId = String(purpose.matchId || "");
    if (!matchId) throw new HttpError(400, "Missing matchId");
    const snap = await db.collection("matches").doc(matchId).get();
    const m = snap.exists ? snap.data() : null;
    if (!m || m.locationId !== venueId) throw new HttpError(403, "Invalid booking");

    if (purpose.kind === "booking") {
      if (m.hostUid !== uid) throw new HttpError(403, "Invalid booking");
      if (m.paymentStatus !== "awaiting_payment") throw new HttpError(409, "Booking not awaiting payment");
      return {meta: {kind: "booking", matchId}, amountRon: null};
    }

    // Partea unui jucător la o rezervare împărțită.
    const joined = Array.isArray(m.joinedUids) ? m.joinedUids : [];
    if (m.hostUid === uid || !joined.includes(uid)) throw new HttpError(403, "Not a player of this match");
    if (m.paymentMode !== "split" || m.paymentStatus !== "confirmed" || m.status === "cancelled") {
      throw new HttpError(409, "Match does not accept share payments");
    }
    if (hasStarted(m)) throw new HttpError(409, "Match already started");
    const existing = paymentsOf(m)[uid];
    if (existing && remainingOf(existing) > 0) throw new HttpError(409, "Share already paid");
    const share = shareAmountFor(m);
    if (share < MIN_SHARE_RON) throw new HttpError(409, "Share too small");
    return {meta: {kind: "share", matchId}, amountRon: share};
  }

  if (purpose.kind === "pass") {
    return {
      meta: {
        kind: "pass",
        passType: String(purpose.passType || "").slice(0, 100),
        passEntries: String(purpose.passEntries || "").slice(0, 20),
      },
      amountRon: null,
    };
  }
  return {meta: {}, amountRon: null};
}

// Notă pe rezervare: ce plată îi aparține (ca releaseUnpaidHolds să o poată închide).
async function attachPaymentRef(meta, ref) {
  if (meta.kind !== "booking") return;
  await admin.firestore().collection("matches").doc(meta.matchId).update(ref).catch(() => {});
}

async function notify(toUid, type, titleKey, bodyKey, args, matchId) {
  if (!toUid) return;
  await admin.firestore().collection("notifications").add({
    toUid,
    fromUid: "",
    fromUsername: "",
    fromAvatarUrl: "",
    titleKey,
    bodyKey,
    args: args || {},
    title: "Playhub",
    body: "",
    type,
    status: "pending",
    matchId: matchId || "",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function hourLabel(h) {
  const n = Number(h);
  if (!Number.isFinite(n)) return "-";
  const hh = Math.floor(n);
  const mm = Math.round((n - hh) * 60);
  return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0");
}

// Aceleași argumente ca NotificationService.matchArgs din aplicație.
function matchArgs(m) {
  return {
    date: String(m.date || "-"),
    time: hourLabel(m.startHour) + " - " + hourLabel(m.endHour),
    venue: String(m.locationName || "-"),
    table: String(m.tableId === undefined || m.tableId === null ? "-" : m.tableId),
  };
}

const playerName = (m, uid) => {
  const p = (m.joinedPlayers || []).find((x) => x && x.uid === uid);
  return String((p && p.username) || (uid === m.hostUid ? m.hostUsername : "") || "");
};

// Rambursare (parțială sau totală) a unei plăți. La plățile către o sală cu Stripe Connect,
// partea sălii se recuperează din contul ei (reverse_transfer).
async function refundPayment(stripe, piId, amountRon, key) {
  const bani = toBani(amountRon);
  if (!piId || bani <= 0) return 0;
  const pi = await stripe.paymentIntents.retrieve(piId);
  const params = {payment_intent: piId, amount: bani};
  if (pi.transfer_data && pi.transfer_data.destination) params.reverse_transfer = true;
  await stripe.refunds.create(params, {idempotencyKey: key});
  return round2(bani / 100);
}

// Plata a reușit (din webhook: payment_intent.succeeded sau checkout.session.completed).
// Idempotentă: Stripe poate trimite evenimentul de mai multe ori.
async function confirmPayment(stripe, pi) {
  const meta = pi.metadata || {};
  const db = admin.firestore();
  const amountRon = (pi.amount_received || pi.amount || 0) / 100;

  if (meta.kind === "booking" && meta.matchId) {
    const ref = db.collection("matches").doc(meta.matchId);
    let match = null;
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return "missing";
      const m = snap.data();
      match = m;
      if (m.stripePaymentIntentId === pi.id && m.paymentStatus === "confirmed") return "already";
      if (m.status === "cancelled" || m.paymentStatus !== "awaiting_payment") return "not_awaiting";
      const update = {
        "paymentStatus": "confirmed",
        "stripePaymentIntentId": pi.id,
        "paidAmount": amountRon,
        "paidAt": admin.firestore.FieldValue.serverTimestamp(),
        ["cardPayments." + m.hostUid]: {pi: pi.id, amount: amountRon, refunded: 0, role: "host"},
      };
      if (m.paymentMode === "split") {
        const seats = Number(m.maxPlayers) || 1;
        update.shareAmount = round2(amountRon / seats);
        update.hostReimbursed = false;
      }
      tx.update(ref, update);
      return "confirmed";
    });

    if (outcome === "missing" || outcome === "not_awaiting") {
      // Rezervarea nu mai există sau a fost deja anulată: banii se întorc la jucător.
      await refundPayment(stripe, pi.id, amountRon, "refund_" + pi.id);
      await notify(meta.uid, "payment_refunded", "n.pay_refund_title", "n.pay_refund_body",
          {amount: amountRon.toFixed(2)}, meta.matchId);
      console.warn("Plată rambursată automat (rezervare " + outcome + "):", meta.matchId, pi.id);
    } else if (outcome === "confirmed" && match) {
      // Notificările de rezervare pleacă de aici (nu din aplicație), ca să ajungă și dacă
      // aplicația s-a închis sau s-a reîncărcat în timpul plății.
      const args = {...matchArgs(match), player: String(match.hostUsername || "")};
      await notify(match.locationId, "booking_new", "n.booking_venue_title", "n.booking_venue_body", args, meta.matchId);
      await notify(match.hostUid, "booking_confirmed", "n.booking_host_title", "n.booking_host_body", args, meta.matchId);
    }
    return outcome;
  }

  if (meta.kind === "share" && meta.matchId && meta.uid) {
    const ref = db.collection("matches").doc(meta.matchId);
    const uid = meta.uid;
    let match = null;
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return "missing";
      const m = snap.data();
      match = m;
      const existing = paymentsOf(m)[uid];
      if (existing && existing.pi === pi.id) return "already";
      const joined = Array.isArray(m.joinedUids) ? m.joinedUids : [];
      const valid = m.paymentMode === "split" && m.paymentStatus === "confirmed" &&
        m.status !== "cancelled" && joined.includes(uid) && uid !== m.hostUid && !hasStarted(m) &&
        !(existing && remainingOf(existing) > 0);
      if (!valid) return "invalid";
      tx.update(ref, {["cardPayments." + uid]: {pi: pi.id, amount: amountRon, refunded: 0, role: "share"}});
      return "share_paid";
    });

    if (outcome === "missing" || outcome === "invalid") {
      await refundPayment(stripe, pi.id, amountRon, "refund_" + pi.id);
      await notify(uid, "payment_refunded", "n.pay_refund_title", "n.pay_refund_body",
          {amount: amountRon.toFixed(2)}, meta.matchId);
      console.warn("Parte rambursată automat (" + outcome + "):", meta.matchId, pi.id);
    } else if (outcome === "share_paid" && match) {
      await notify(match.hostUid, "share_paid", "n.share_paid_title", "n.share_paid_body",
          {...matchArgs(match), player: playerName(match, uid), amount: amountRon.toFixed(2)}, meta.matchId);
    }
    return outcome;
  }

  if (meta.kind === "pass" && meta.uid) {
    // Abonament la sală: un document per plată (id = PaymentIntent), deci fără dubluri.
    await db.collection("users").doc(meta.uid).collection("subscriptions").doc(pi.id).set({
      venueId: meta.venueId || "",
      type: meta.passType || "",
      entries: meta.passEntries ? Number(meta.passEntries) || meta.passEntries : null,
      price: amountRon,
      stripePaymentIntentId: pi.id,
      purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return "pass";
  }
  return "ignored";
}

async function isAdminUser(decoded) {
  if (decoded.email === SUPER_ADMIN_EMAIL) return true;
  const u = await admin.firestore().collection("users").doc(decoded.uid).get();
  return u.exists && u.data().isAdmin === true;
}

// Renunțare / anulare la o rezervare plătită cu cardul, cu rambursare reală prin Stripe.
//  - action "leave": un jucător (nu gazda) iese din meci și primește înapoi partea plătită;
//  - action "cancel": gazda, sala sau un admin anulează rezervarea; toți primesc banii înapoi.
// Jucătorii o pot face oricând până la începerea meciului; sala și adminul și după.
// silent: sala / adminul trimit ei înșiși anunțul de anulare (cu motivul), deci serverul nu-l mai trimite.
async function cancelCardBooking(stripe, decoded, matchId, action, {silent = false} = {}) {
  const db = admin.firestore();
  const ref = db.collection("matches").doc(String(matchId || ""));
  const uid = decoded.uid;
  const adminUser = action === "cancel" ? await isAdminUser(decoded) : false;

  const plan = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpError(404, "Match not found");
    const m = snap.data();
    if (m.status === "cancelled") throw new HttpError(409, "Match already cancelled");
    const joined = Array.isArray(m.joinedUids) ? m.joinedUids : [];
    const payments = paymentsOf(m);
    const isVenue = m.locationId === uid;

    if (action === "leave") {
      if (uid === m.hostUid) throw new HttpError(400, "The host cancels the booking instead");
      if (!joined.includes(uid)) throw new HttpError(403, "Not a player of this match");
      if (hasStarted(m)) throw new HttpError(409, "Match already started");
      const p = payments[uid];
      const amount = p ? remainingOf(p) : 0;
      const players = (m.joinedPlayers || []).filter((x) => !(x && x.uid === uid));
      const update = {
        joinedPlayers: players,
        joinedUids: joined.filter((x) => x !== uid),
        status: "open",
      };
      if (p) update["cardPayments." + uid] = {...p, refunded: round2((Number(p.refunded) || 0) + amount)};
      tx.update(ref, update);
      return {m, refunds: amount > 0 ? [{uid, pi: p.pi, amount}] : [], type: "leave"};
    }

    if (action === "cancel") {
      if (!(uid === m.hostUid || isVenue || adminUser)) throw new HttpError(403, "Not allowed");
      if (uid === m.hostUid && !isVenue && !adminUser && hasStarted(m)) {
        throw new HttpError(409, "Match already started");
      }
      const refunds = [];
      const update = {
        status: "cancelled",
        cancelledBy: uid,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      let total = 0;
      for (const [pUid, p] of Object.entries(payments)) {
        const amount = remainingOf(p);
        if (amount <= 0) continue;
        refunds.push({uid: pUid, pi: p.pi, amount});
        total += amount;
        update["cardPayments." + pUid] = {...p, refunded: round2((Number(p.refunded) || 0) + amount)};
      }
      if (total > 0) {
        update.paymentStatus = "refunded";
        update.refundedAmount = round2((Number(m.refundedAmount) || 0) + total);
      }
      tx.update(ref, update);
      return {m, refunds, type: "cancel", quiet: silent && (isVenue || adminUser)};
    }
    throw new HttpError(400, "Invalid action");
  });

  // Rambursările se fac după ce rezervarea e actualizată (cheie unică per plată: fără dubluri).
  let refundedToCaller = 0;
  let refundedTotal = 0;
  for (const r of plan.refunds) {
    try {
      const done = await refundPayment(stripe, r.pi, r.amount, plan.type + "_" + matchId + "_" + r.pi);
      refundedTotal += done;
      if (r.uid === uid) refundedToCaller += done;
      if (r.uid !== uid) {
        await notify(r.uid, "payment_refunded", "n.pay_refund_title", "n.pay_back_body",
            {...matchArgs(plan.m), amount: done.toFixed(2)}, matchId);
      }
    } catch (e) {
      console.error("Rambursare eșuată", matchId, r, e);
      await ref.update({refundErrors: admin.firestore.FieldValue.arrayUnion(r.pi)}).catch(() => {});
    }
  }

  const m = plan.m;
  const args = matchArgs(m);
  if (plan.type === "leave") {
    const leftArgs = {...args, player: playerName(m, uid)};
    await notify(m.hostUid, "match_left", "n.left_title", "n.left_body", leftArgs, matchId);
    await notify(m.locationId, "match_left", "n.left_title", "n.left_body", leftArgs, matchId);
  } else if (!plan.quiet) {
    const by = uid === m.locationId ? String(m.locationName || "") : playerName(m, uid);
    const targets = new Set([...(m.joinedUids || []), m.locationId].filter(Boolean));
    targets.delete(uid);
    for (const t of targets) {
      await notify(t, "match_cancel", "n.cancel_title", "n.cancel_body", {...args, by}, matchId);
    }
  }
  return {ok: true, refunded: round2(refundedToCaller), refundedTotal: round2(refundedTotal)};
}

// La ora de început: gazdei i se returnează părțile plătite de jucătorii rămași în meci
// (până atunci oricine putea renunța cu rambursare completă, iar sala rămâne plătită).
async function settleSplit(stripe, ref, m) {
  const payments = paymentsOf(m);
  const host = payments[m.hostUid];
  const joined = new Set(m.joinedUids || []);
  let others = 0;
  for (const [pUid, p] of Object.entries(payments)) {
    if (pUid === m.hostUid || p.role !== "share" || !joined.has(pUid)) continue;
    others += remainingOf(p);
  }
  let refund = 0;
  if (host) {
    const cap = remainingOf(host) - shareAmountFor(m);
    refund = round2(Math.max(Math.min(others, cap), 0));
  }
  if (refund > 0) {
    refund = await refundPayment(stripe, host.pi, refund, "reimburse_" + ref.id);
  }
  const update = {hostReimbursed: true, hostReimbursedAmount: refund};
  if (host && refund > 0) {
    update["cardPayments." + m.hostUid] = {...host, refunded: round2((Number(host.refunded) || 0) + refund)};
  }
  await ref.update(update);
  if (refund > 0) {
    await notify(m.hostUid, "split_reimbursed", "n.reimbursed_title", "n.reimbursed_body",
        {...matchArgs(m), amount: refund.toFixed(2)}, ref.id);
  }
  return refund;
}

exports.cancelCardBooking = onRequest(
    {cors: true, region: REGION, secrets: [STRIPE_SECRET_KEY]},
    async (req, res) => {
      if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
      const header = req.get("Authorization") || "";
      const match = header.match(/^Bearer (.+)$/);
      if (!match) return res.status(401).json({error: "Missing auth token"});
      let decoded;
      try {
        decoded = await admin.auth().verifyIdToken(match[1]);
      } catch (e) {
        return res.status(401).json({error: "Invalid auth token"});
      }
      try {
        const {matchId, action, silent} = req.body || {};
        const result = await cancelCardBooking(getStripe(), decoded, matchId, action, {silent: silent === true});
        res.status(200).json(result);
      } catch (e) {
        if (e instanceof HttpError) return res.status(e.status).json({error: e.message});
        console.error("cancelCardBooking", e);
        res.status(500).json({error: "Cancel failed"});
      }
    },
);

exports.settleSplitPayments = onSchedule(
    {schedule: "every 15 minutes", region: REGION, secrets: [STRIPE_SECRET_KEY], timeoutSeconds: 120},
    async () => {
      const db = admin.firestore();
      const stripe = getStripe();
      const snap = await db.collection("matches")
          .where("paymentMode", "==", "split").where("hostReimbursed", "==", false).get();
      let settled = 0;
      for (const doc of snap.docs) {
        const m = doc.data();
        if (m.paymentStatus !== "confirmed" || m.status === "cancelled" || !hasStarted(m)) continue;
        try {
          await settleSplit(stripe, doc.ref, m);
          settled++;
        } catch (e) {
          console.error("settleSplitPayments", doc.id, e);
        }
      }
      if (settled) console.log("Rezervări împărțite decontate: " + settled);
    },
);

// Rezervări rămase neplătite: plata se închide, iar masa se eliberează.
exports.releaseUnpaidHolds = onSchedule(
    {schedule: "every 10 minutes", region: REGION, secrets: [STRIPE_SECRET_KEY], timeoutSeconds: 120},
    async () => {
      const db = admin.firestore();
      const stripe = getStripe();
      const cutoff = Date.now() - HOLD_MINUTES * 60000;
      const snap = await db.collection("matches").where("paymentStatus", "==", "awaiting_payment").get();
      let released = 0;
      for (const doc of snap.docs) {
        const m = doc.data();
        const created = m.createdAt && m.createdAt.toMillis ? m.createdAt.toMillis() : 0;
        if (created > cutoff) continue;
        try {
          // Dacă plata a reușit totuși, confirmăm în loc să ștergem.
          if (m.checkoutSessionId) {
            let s = await stripe.checkout.sessions.retrieve(m.checkoutSessionId);
            if (s.status === "open") {
              try {
                s = await stripe.checkout.sessions.expire(m.checkoutSessionId);
              } catch (e) {
                s = await stripe.checkout.sessions.retrieve(m.checkoutSessionId);
              }
            }
            if (s.payment_status === "paid" && s.payment_intent) {
              await confirmPayment(stripe, await stripe.paymentIntents.retrieve(s.payment_intent));
              continue;
            }
          }
          if (m.paymentIntentId) {
            const pi = await stripe.paymentIntents.retrieve(m.paymentIntentId);
            if (pi.status === "succeeded") {
              await confirmPayment(stripe, pi);
              continue;
            }
            if (!["canceled", "succeeded"].includes(pi.status)) {
              await stripe.paymentIntents.cancel(pi.id).catch(() => {});
            }
          }
          await doc.ref.delete();
          released++;
        } catch (e) {
          console.error("releaseUnpaidHolds", doc.id, e);
        }
      }
      if (released) console.log("Rezervări neplătite eliberate: " + released);
    },
);

exports.purposeMetadata = purposeMetadata;
exports.attachPaymentRef = attachPaymentRef;
exports.confirmPayment = confirmPayment;
exports.cancelCardBookingCore = cancelCardBooking;
exports.settleSplit = settleSplit;
exports.shareAmountFor = shareAmountFor;
exports.HttpError = HttpError;
exports.HOLD_MINUTES = HOLD_MINUTES;
exports.PLATFORM_FEE_RON = PLATFORM_FEE_RON;
