// Abonamentul lunar al sălilor (Stripe Billing).
//
// Fluxul:
//  1. Sala apasă „Activează abonamentul" în aplicație → createVenueSubscriptionCheckout întoarce un link
//     Stripe Checkout (100 RON / lună) → sala plătește pe pagina Stripe.
//  2. Stripe cheamă stripeWebhook la fiecare schimbare (plătit, restant, anulat) →
//     scriem starea în venues/{id}.billing (doar aici; sala nu poate scrie câmpul `billing`).
//  3. createVenueBillingPortal deschide portalul Stripe (schimbare card, facturi, anulare).
//
// Setup (o singură dată):
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   (valoarea whsec_... din Stripe, vezi mai jos)
//   firebase deploy --only functions
//   Stripe Dashboard → Developers → Webhooks → Add endpoint:
//     URL:     https://us-central1-pingpongplayhub1.cloudfunctions.net/stripeWebhook
//     Events:  checkout.session.completed, customer.subscription.created,
//              customer.subscription.updated, customer.subscription.deleted
//     (copiezi „Signing secret" whsec_... în comanda de mai sus, apoi redeploy)
//   Stripe Dashboard → Settings → Billing → Customer portal → Activate (pentru butonul „Gestionează").
const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const bookings = require("./bookings");

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

const SUBSCRIPTION_BANI = 10000; // 100 RON / lună
const SITE = "https://pingpongplayhub1.web.app";

function getStripe() {
  return require("stripe")(STRIPE_SECRET_KEY.value());
}

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

// Doar conturile de sală (există venues/{uid}) pot cere abonament.
async function loadVenue(uid) {
  const ref = admin.firestore().collection("venues").doc(uid);
  const snap = await ref.get();
  return snap.exists ? {ref, data: snap.data()} : null;
}

async function ensureCustomer(stripe, venue, decoded) {
  const existing = venue.data.billing && venue.data.billing.stripeCustomerId;
  if (existing) return existing;
  const customer = await stripe.customers.create({
    email: venue.data.email || decoded.email || undefined,
    name: venue.data.venueName || undefined,
    metadata: {venueId: venue.ref.id},
  });
  await venue.ref.set({billing: {stripeCustomerId: customer.id}}, {merge: true});
  return customer.id;
}

const options = {cors: true, secrets: [STRIPE_SECRET_KEY]};

exports.createVenueSubscriptionCheckout = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  try {
    const venue = await loadVenue(decoded.uid);
    if (!venue) return res.status(403).json({error: "Not a venue account"});

    const stripe = getStripe();
    const customer = await ensureCustomer(stripe, venue, decoded);
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "ron",
          unit_amount: SUBSCRIPTION_BANI,
          recurring: {interval: "month"},
          product_data: {name: "Playhub - abonament lunar sală"},
        },
      }],
      subscription_data: {metadata: {venueId: decoded.uid}},
      metadata: {venueId: decoded.uid},
      success_url: SITE + "/?billing=success",
      cancel_url: SITE + "/?billing=cancel",
    });
    res.status(200).json({url: session.url});
  } catch (error) {
    console.error("Subscription checkout error:", error);
    res.status(500).json({error: "Could not start checkout"});
  }
});

exports.createVenueBillingPortal = onRequest(options, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  const decoded = await authenticate(req, res);
  if (!decoded) return;
  try {
    const venue = await loadVenue(decoded.uid);
    const customer = venue && venue.data.billing && venue.data.billing.stripeCustomerId;
    if (!customer) return res.status(400).json({error: "No billing account"});
    const session = await getStripe().billingPortal.sessions.create({
      customer,
      return_url: SITE + "/",
    });
    res.status(200).json({url: session.url});
  } catch (error) {
    console.error("Billing portal error:", error);
    res.status(500).json({error: "Could not open portal"});
  }
});

async function notifyVenue(venueId, titleKey, bodyKey) {
  await admin.firestore().collection("notifications").add({
    toUid: venueId,
    fromUid: "",
    fromUsername: "",
    fromAvatarUrl: "",
    titleKey,
    bodyKey,
    args: {},
    title: "Playhub",
    body: "",
    type: "subscription",
    status: "pending",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function syncSubscription(sub) {
  const db = admin.firestore();
  let venueId = sub.metadata && sub.metadata.venueId;
  if (!venueId) {
    const q = await db.collection("venues")
        .where("billing.stripeCustomerId", "==", sub.customer).limit(1).get();
    if (q.empty) return;
    venueId = q.docs[0].id;
  }
  const ref = db.collection("venues").doc(venueId);
  const before = await ref.get();
  const prevStatus = before.exists && before.data().billing ? before.data().billing.status : null;

  const end = sub.current_period_end ||
    (sub.items && sub.items.data && sub.items.data[0] && sub.items.data[0].current_period_end);
  const billing = {
    status: sub.status, // active | trialing | past_due | unpaid | canceled | incomplete ...
    stripeSubscriptionId: sub.id,
    stripeCustomerId: sub.customer,
    cancelAtPeriodEnd: !!sub.cancel_at_period_end,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (end) billing.currentPeriodEnd = admin.firestore.Timestamp.fromMillis(end * 1000);
  await ref.set({billing}, {merge: true});

  if (prevStatus !== sub.status) {
    if (sub.status === "active") {
      await notifyVenue(venueId, "n.sub_active_title", "n.sub_active_body");
    } else if (sub.status === "past_due" || sub.status === "unpaid") {
      await notifyVenue(venueId, "n.sub_failed_title", "n.sub_failed_body");
    }
  }
}

exports.stripeWebhook = onRequest(
    {secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET]},
    async (req, res) => {
      if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
      const stripe = getStripe();
      let event;
      try {
        event = stripe.webhooks.constructEvent(
            req.rawBody, req.get("stripe-signature"), STRIPE_WEBHOOK_SECRET.value());
      } catch (e) {
        console.error("Webhook signature error:", e.message);
        return res.status(400).send("Bad signature");
      }

      try {
        const obj = event.data.object;
        if (event.type.startsWith("customer.subscription.")) {
          await syncSubscription(obj);
        } else if (event.type === "checkout.session.completed" &&
                   obj.mode === "subscription" && obj.subscription) {
          await syncSubscription(await stripe.subscriptions.retrieve(obj.subscription));
        } else if (event.type === "checkout.session.completed" &&
                   obj.mode === "payment" && obj.payment_status === "paid" && obj.payment_intent) {
          // Rezervare / abonament de sală plătit pe web (Stripe Checkout).
          await bookings.confirmPayment(stripe, await stripe.paymentIntents.retrieve(obj.payment_intent));
        } else if (event.type === "payment_intent.succeeded") {
          // Plată din aplicația de telefon (PaymentSheet) sau din Checkout.
          await bookings.confirmPayment(stripe, obj);
        }
      } catch (e) {
        console.error("Webhook handler error:", e);
        return res.status(500).send("Handler error"); // Stripe reîncearcă
      }
      res.json({received: true});
    },
);
