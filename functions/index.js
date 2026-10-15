const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

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

exports.createStripePaymentIntent = onRequest(options, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method Not Allowed");
  }
  const decoded = await authenticate(req, res);
  if (!decoded) return;

  try {
    const {amount, venueId} = req.body || {};

    const amountRon = Number(amount);
    if (!Number.isFinite(amountRon) ||
        amountRon < MIN_AMOUNT_RON || amountRon > MAX_AMOUNT_RON) {
      return res.status(400).json({error: "Invalid amount"});
    }
    if (typeof venueId !== "string" || venueId.length === 0) {
      return res.status(400).json({error: "Missing venueId"});
    }

    const amountInBani = Math.round(amountRon * 100);

    const config = {
      amount: amountInBani,
      currency: "ron", // fix, nu mai vine de la client
      automatic_payment_methods: {enabled: true},
      metadata: {venueId, uid: decoded.uid},
    };

    // Contul de destinație se citește din Firestore, nu de la client.
    const venueDoc = await admin.firestore().collection("venues").doc(venueId).get();
    const destination = venueDoc.exists ? venueDoc.data().stripeAccountId : null;
    if (destination && amountInBani > PLATFORM_FEE_BANI) {
      config.transfer_data = {destination};
      config.application_fee_amount = PLATFORM_FEE_BANI;
    }

    const paymentIntent = await getStripe().paymentIntents.create(config);

    res.status(200).json({
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: "",
      customer: "",
    });
  } catch (error) {
    console.error("Stripe Error:", error);
    res.status(500).json({error: "Payment initialization failed"});
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
