// Vouchere / coduri de reducere create de săli.
//
// Documentele stau în `vouchers/{venueId}_{COD}` și le poate citi/edita doar sala (regulile Firestore).
// Jucătorii nu văd codurile: ele se verifică și se folosesc doar prin funcțiile de mai jos.
//
// - checkVoucher:   verifică un cod și întoarce reducerea (fără efecte).
// - redeemVoucher:  rezervă o folosire a codului (atomic) și întoarce reducerea + id-ul folosirii.
// - releaseVoucher: eliberează o folosire rezervată (plată anulată, masă ocupată în ultima clipă).
//
// Câmpuri voucher: venueId, code, type ('percent' | 'fixed'), value, validFrom/validTo (yyyy-MM-dd),
// maxUses (0 = nelimitat), usedCount, perUserOnce, minAmount, active.
//
// Vouchere globale (valabile la orice sală, create de platformă): `vouchers/global_{COD}`.
// Cele din GLOBAL_DEFAULTS se creează automat la prima folosire; valorile se pot edita apoi din consola Firebase.
// Un cod de sală (`{venueId}_{COD}`) are prioritate față de unul global cu același nume.
//
// Deploy: firebase deploy --only functions
const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MAX_AMOUNT_RON = 2000;

// Codurile globale predefinite. `newUsersOnly`: doar conturi care nu au făcut încă nicio rezervare.
const GLOBAL_DEFAULTS = {
  BUNVENIT: {
    type: "fixed",
    value: 20,
    validFrom: "",
    validTo: "",
    maxUses: 0,
    perUserOnce: true,
    newUsersOnly: true,
    minAmount: 0,
    active: true,
  },
};
const MAX_FAILED_ATTEMPTS = 10; // coduri greșite pe oră, per utilizator
const ATTEMPT_WINDOW_MS = 60 * 60 * 1000;

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

function normalizeCode(raw) {
  const code = String(raw || "").trim().toUpperCase().replace(/\s+/g, "");
  return /^[A-Z0-9_-]{3,24}$/.test(code) ? code : null;
}

function todayBucharest() {
  // yyyy-MM-dd în fusul României (valabilitatea se dă pe zile calendaristice)
  return new Intl.DateTimeFormat("en-CA", {timeZone: "Europe/Bucharest"}).format(new Date());
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

// Întoarce {ok:false, reason} sau {ok:true, discount}. `data` e documentul voucherului.
function evaluate(data, amount) {
  if (!data || data.active === false) return {ok: false, reason: "inactive"};
  const today = todayBucharest();
  if (data.validFrom && today < data.validFrom) return {ok: false, reason: "not_started"};
  if (data.validTo && today > data.validTo) return {ok: false, reason: "expired"};
  const maxUses = Number(data.maxUses || 0);
  if (maxUses > 0 && Number(data.usedCount || 0) >= maxUses) return {ok: false, reason: "exhausted"};
  const minAmount = Number(data.minAmount || 0);
  if (minAmount > 0 && amount < minAmount) return {ok: false, reason: "min_amount", minAmount};

  const value = Number(data.value || 0);
  let discount = 0;
  if (data.type === "fixed") {
    discount = Math.min(value, amount);
  } else {
    discount = amount * Math.min(Math.max(value, 0), 100) / 100;
  }
  discount = round2(Math.min(discount, amount));
  if (!(discount > 0)) return {ok: false, reason: "inactive"};
  return {ok: true, discount};
}

function parseInput(body) {
  const venueId = typeof body.venueId === "string" ? body.venueId.trim() : "";
  const code = normalizeCode(body.code);
  const amount = Number(body.amount);
  if (!venueId || !Number.isFinite(amount) || amount <= 0 || amount > MAX_AMOUNT_RON) return null;
  return {venueId, code, amount};
}

// Număr limitat de coduri inexistente pe oră, ca să nu se poată ghici coduri.
async function failedAttemptsExceeded(db, uid) {
  const snap = await db.collection("voucher_attempts").doc(uid).get();
  if (!snap.exists) return false;
  const d = snap.data();
  if (Date.now() - Number(d.windowStart || 0) > ATTEMPT_WINDOW_MS) return false;
  return Number(d.count || 0) >= MAX_FAILED_ATTEMPTS;
}

async function registerFailure(db, uid) {
  const ref = db.collection("voucher_attempts").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const d = snap.exists ? snap.data() : null;
    if (!d || now - Number(d.windowStart || 0) > ATTEMPT_WINDOW_MS) {
      tx.set(ref, {windowStart: now, count: 1});
    } else {
      tx.update(ref, {count: Number(d.count || 0) + 1});
    }
  });
}

// Alege documentul voucherului: întâi codul sălii, apoi (dacă există) cel global.
async function resolveVoucherRef(db, venueId, code) {
  const venueRef = db.collection("vouchers").doc(`${venueId}_${code}`);
  const venueSnap = await venueRef.get();
  if (venueSnap.exists) return venueRef;
  const defaults = GLOBAL_DEFAULTS[code];
  if (!defaults) return venueRef;
  const globalRef = db.collection("vouchers").doc(`global_${code}`);
  try {
    await globalRef.create({
      ...defaults,
      venueId: "global",
      code,
      usedCount: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // există deja (cod 6 = ALREADY_EXISTS)
  }
  return globalRef;
}

// Cont nou = nicio rezervare creată ca gazdă.
async function isNewUser(db, uid) {
  const snap = await db.collection("matches").where("hostUid", "==", uid).limit(1).get();
  return snap.empty;
}

async function userAlreadyUsed(tx, voucherRef, uid) {
  const q = voucherRef.collection("redemptions").where("uid", "==", uid).where("status", "==", "active").limit(1);
  const snap = await tx.get(q);
  return !snap.empty;
}

exports.checkVoucher = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  try {
    const input = parseInput(req.body || {});
    if (!input) return res.status(400).json({error: "Invalid input"});
    const db = admin.firestore();
    if (!input.code) return res.status(200).json({ok: false, reason: "not_found"});
    if (await failedAttemptsExceeded(db, decoded.uid)) {
      return res.status(200).json({ok: false, reason: "too_many_attempts"});
    }
    const ref = await resolveVoucherRef(db, input.venueId, input.code);
    const snap = await ref.get();
    if (!snap.exists) {
      await registerFailure(db, decoded.uid);
      return res.status(200).json({ok: false, reason: "not_found"});
    }
    if (snap.data().newUsersOnly === true && !(await isNewUser(db, decoded.uid))) {
      return res.status(200).json({ok: false, reason: "not_new_user"});
    }
    const result = evaluate(snap.data(), input.amount);
    if (result.ok && snap.data().perUserOnce === true) {
      const used = await db.runTransaction((tx) => userAlreadyUsed(tx, ref, decoded.uid));
      if (used) return res.status(200).json({ok: false, reason: "already_used"});
    }
    return res.status(200).json(result.ok ?
      {ok: true, discount: result.discount, code: input.code, type: snap.data().type, value: snap.data().value} :
      result);
  } catch (e) {
    console.error("checkVoucher", e);
    return res.status(500).json({error: "Internal error"});
  }
});

exports.redeemVoucher = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  try {
    const input = parseInput(req.body || {});
    if (!input || !input.code) return res.status(400).json({error: "Invalid input"});
    const db = admin.firestore();
    if (await failedAttemptsExceeded(db, decoded.uid)) {
      return res.status(200).json({ok: false, reason: "too_many_attempts"});
    }
    const ref = await resolveVoucherRef(db, input.venueId, input.code);
    const preSnap = await ref.get();
    if (preSnap.exists && preSnap.data().newUsersOnly === true && !(await isNewUser(db, decoded.uid))) {
      return res.status(200).json({ok: false, reason: "not_new_user"});
    }

    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return {ok: false, reason: "not_found"};
      const data = snap.data();
      const result = evaluate(data, input.amount);
      if (!result.ok) return result;
      if (data.perUserOnce === true && await userAlreadyUsed(tx, ref, decoded.uid)) {
        return {ok: false, reason: "already_used"};
      }
      const redemptionRef = ref.collection("redemptions").doc();
      tx.set(redemptionRef, {
        uid: decoded.uid,
        discount: result.discount,
        amount: input.amount,
        status: "active",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(ref, {usedCount: admin.firestore.FieldValue.increment(1)});
      return {ok: true, discount: result.discount, code: input.code, voucherId: ref.id, redemptionId: redemptionRef.id};
    });
    if (!out.ok && out.reason === "not_found") await registerFailure(db, decoded.uid);
    return res.status(200).json(out);
  } catch (e) {
    console.error("redeemVoucher", e);
    return res.status(500).json({error: "Internal error"});
  }
});

exports.releaseVoucher = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  try {
    const {voucherId, redemptionId} = req.body || {};
    if (typeof voucherId !== "string" || typeof redemptionId !== "string" || !voucherId || !redemptionId) {
      return res.status(400).json({error: "Invalid input"});
    }
    const db = admin.firestore();
    const ref = db.collection("vouchers").doc(voucherId);
    const redRef = ref.collection("redemptions").doc(redemptionId);
    const released = await db.runTransaction(async (tx) => {
      const [vSnap, rSnap] = await Promise.all([tx.get(ref), tx.get(redRef)]);
      if (!rSnap.exists || !vSnap.exists) return false;
      const r = rSnap.data();
      if (r.uid !== decoded.uid || r.status !== "active") return false;
      tx.update(redRef, {status: "released", releasedAt: admin.firestore.FieldValue.serverTimestamp()});
      tx.update(ref, {usedCount: Math.max(0, Number(vSnap.data().usedCount || 0) - 1)});
      return true;
    });
    return res.status(200).json({ok: true, released});
  } catch (e) {
    console.error("releaseVoucher", e);
    return res.status(500).json({error: "Internal error"});
  }
});
