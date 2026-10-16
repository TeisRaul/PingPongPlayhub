const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const bookings = require("./bookings");

// Cheia secretă Stripe NU se mai ține în cod. Se setează o singură dată cu:
//   firebase functions:secrets:set STRIPE_SECRET_KEY
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

const PLATFORM_FEE_BANI = 500; // 5 RON
const MIN_AMOUNT_RON = 1;
const MAX_AMOUNT_RON = 2000;

function getStripe() {
  return require("stripe")(STRIPE_SECRET_KEY.value());
}

// Verifică Firebase ID token din header-ul Authorization: Bearer <token>.
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

const options = {cors: true, secrets: [STRIPE_SECRET_KEY]};

// Datele comune ale unei plăți: suma (calculată pe server unde se poate), scopul, contul sălii.
async function preparePayment(body, decoded) {
  const {amount, venueId, purpose} = body || {};
  if (typeof venueId !== "string" || venueId.length === 0) {
    throw new bookings.HttpError(400, "Missing venueId");
  }
  const {meta, amountRon: serverAmount} = await bookings.purposeMetadata(purpose, decoded.uid, venueId);
  const amountRon = serverAmount !== null ? serverAmount : Number(amount);
  if (!Number.isFinite(amountRon) || amountRon < MIN_AMOUNT_RON || amountRon > MAX_AMOUNT_RON) {
    throw new bookings.HttpError(400, "Invalid amount");
  }
  const amountInBani = Math.round(amountRon * 100);

  // Contul de destinație se citește din Firestore, nu de la client.
  const venueDoc = await admin.firestore().collection("venues").doc(venueId).get();
  const venue = venueDoc.exists ? venueDoc.data() : {};
  const destination = venue.stripeAccountId || null;

  // Taxa platformei se reține o singură dată, din plata gazdei; părțile jucătorilor merg integral la sală.
  let transfer = null;
  if (destination && amountInBani > PLATFORM_FEE_BANI) {
    transfer = {transfer_data: {destination}};
    if (meta.kind !== "share") transfer.application_fee_amount = PLATFORM_FEE_BANI;
  } else if (destination && meta.kind === "share") {
    transfer = {transfer_data: {destination}};
  }
  return {amountInBani, venueId, venue, meta: {venueId, uid: decoded.uid, ...meta}, transfer};
}

exports.createStripePaymentIntent = onRequest(options, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method Not Allowed");
  }
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const {amountInBani, meta, transfer} = await preparePayment(req.body, decoded);

    const config = {
      amount: amountInBani,
      currency: "ron", // fix, nu mai vine de la client
      automatic_payment_methods: {enabled: true},
      metadata: meta,
      ...(transfer || {}),
    };

    const paymentIntent = await getStripe().paymentIntents.create(config);
    await bookings.attachPaymentRef(config.metadata, {paymentIntentId: paymentIntent.id});

    res.status(200).json({
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: "",
      customer: "",
    });
  } catch (error) {
    if (error instanceof bookings.HttpError) return res.status(error.status).json({error: error.message});
    console.error("Stripe Error:", error);
    res.status(500).json({error: "Payment initialization failed"});
  }
});

// ---------- Plata cu cardul în versiunea web (Stripe Checkout) ----------
// Pe web nu există fereastra de plată nativă (PaymentSheet), așa că aplicația deschide pagina
// Stripe Checkout într-o fereastră nouă și verifică periodic, cu getCheckoutStatus, dacă s-a plătit.
const WEB_BASE_URL = "https://pingpongplayhub1.web.app";
const CHECKOUT_TTL_SEC = 30 * 60; // minimul acceptat de Stripe

exports.createBookingCheckout = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const {amountInBani, venue, meta, transfer} = await preparePayment(req.body, decoded);
    const paymentIntentData = {metadata: {...meta, source: "web_checkout"}, ...(transfer || {})};

    const session = await getStripe().checkout.sessions.create({
      mode: "payment",
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "ron",
          unit_amount: amountInBani,
          product_data: {
            name: (meta.kind === "share" ? "Partea ta - " : "Rezervare Playhub") +
              (venue.name ? (meta.kind === "share" ? "" : " - ") + venue.name : ""),
          },
        },
      }],
      payment_intent_data: paymentIntentData,
      metadata: meta,
      customer_email: decoded.email || undefined,
      locale: "auto",
      expires_at: Math.floor(Date.now() / 1000) + CHECKOUT_TTL_SEC,
      // După plată, pagina plata.html duce jucătorul direct la rezervare (cu biletul QR).
      success_url: WEB_BASE_URL + "/plata.html?status=ok" + (meta.matchId ? "&match=" + encodeURIComponent(meta.matchId) : ""),
      cancel_url: WEB_BASE_URL + "/plata.html?status=anulat",
    });

    await bookings.attachPaymentRef(meta, {checkoutSessionId: session.id});
    res.status(200).json({id: session.id, url: session.url});
  } catch (error) {
    if (error instanceof bookings.HttpError) return res.status(error.status).json({error: error.message});
    console.error("Checkout Error:", error);
    res.status(500).json({error: "Checkout initialization failed"});
  }
});

// Starea unei sesiuni Checkout create de utilizatorul curent: "paid", "open" sau "expired".
// Cu {cancel: true}, o sesiune încă deschisă este închisă, ca să nu mai poată fi plătită după ce
// jucătorul a renunțat în aplicație (dacă între timp a plătit, răspunsul este tot "paid").
exports.getCheckoutStatus = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const {id, cancel} = req.body || {};
    if (typeof id !== "string" || !id.startsWith("cs_")) {
      return res.status(400).json({error: "Invalid session id"});
    }
    const stripe = getStripe();
    let session = await stripe.checkout.sessions.retrieve(id);
    if (!session.metadata || session.metadata.uid !== decoded.uid) {
      return res.status(403).json({error: "Forbidden"});
    }
    if (cancel === true && session.status === "open") {
      try {
        session = await stripe.checkout.sessions.expire(id);
      } catch (e) {
        // A plătit chiar în acel moment: sesiunea nu mai poate fi închisă, citim starea finală.
        session = await stripe.checkout.sessions.retrieve(id);
      }
    }
    let status = "open";
    if (session.payment_status === "paid") status = "paid";
    else if (session.status === "expired") status = "expired";
    res.status(200).json({status});
  } catch (error) {
    console.error("Checkout status error:", error);
    res.status(500).json({error: "Checkout status failed"});
  }
});

exports.createStripeConnectAccount = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const account = await getStripe().accounts.create({
      type: "express",
      email: decoded.email || undefined, // din token, nu de la client
      capabilities: {
        card_payments: {requested: true},
        transfers: {requested: true},
      },
    });
    res.status(200).json({accountId: account.id});
  } catch (error) {
    console.error("Stripe Connect Error:", error);
    res.status(500).json({error: "Could not create account"});
  }
});

exports.createStripeAccountLink = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const {accountId} = req.body || {};
    if (typeof accountId !== "string" || !accountId.startsWith("acct_")) {
      return res.status(400).json({error: "Invalid accountId"});
    }

    // Doar proprietarul sălii care are acest cont Stripe poate cere link-ul.
    const owned = await admin.firestore().collection("venues")
        .where("stripeAccountId", "==", accountId).limit(1).get();
    if (owned.empty || owned.docs[0].id !== decoded.uid) {
      return res.status(403).json({error: "Not allowed"});
    }

    const accountLink = await getStripe().accountLinks.create({
      account: accountId,
      refresh_url: "https://pingpongplayhub.web.app/reauth", // placeholders
      return_url: "https://pingpongplayhub.web.app/return",
      type: "account_onboarding",
    });
    res.status(200).json({url: accountLink.url});
  } catch (error) {
    console.error("Stripe AccountLink Error:", error);
    res.status(500).json({error: "Could not create link"});
  }
});

// Email pentru fiecare notificare (vezi email.js)
exports.sendNotificationEmail = require("./email").sendNotificationEmail;

// Abonamentul lunar al sălilor (vezi billing.js)
const billing = require("./billing");
exports.createVenueSubscriptionCheckout = billing.createVenueSubscriptionCheckout;
exports.createVenueBillingPortal = billing.createVenueBillingPortal;
exports.stripeWebhook = billing.stripeWebhook;

// Export de date și ștergere de cont (vezi account.js)
const account = require("./account");
exports.exportMyData = account.exportMyData;
exports.deleteMyAccount = account.deleteMyAccount;

// Notificări push pe telefon / browser (vezi push.js)
exports.sendPushNotification = require("./push").sendPushNotification;

// Lista de așteptare pentru mese (vezi waitlist.js)
exports.notifyWaitlist = require("./waitlist").notifyWaitlist;

// Vouchere / coduri de reducere (vezi vouchers.js)
const vouchers = require("./vouchers");
exports.checkVoucher = vouchers.checkVoucher;
exports.redeemVoucher = vouchers.redeemVoucher;
exports.releaseVoucher = vouchers.releaseVoucher;

// Remindere înainte de meci, configurabile de jucător (vezi reminders.js; necesită Blaze)
exports.sendMatchReminders = require("./reminders").sendMatchReminders;

// Rezervări plătite cu cardul: eliberarea celor rămase neplătite.
exports.releaseUnpaidHolds = bookings.releaseUnpaidHolds;

// Renunțare / anulare cu rambursare reală și decontarea plăților împărțite.
exports.cancelCardBooking = bookings.cancelCardBooking;
exports.settleSplitPayments = bookings.settleSplitPayments;
