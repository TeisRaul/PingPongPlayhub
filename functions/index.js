const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// Initialize Firebase Admin
admin.initializeApp();

// Hardcoded Stripe Secret Key based on User provision
const stripe = require("stripe")("sk_test_51TavkBFE1XwqOjnW3Z4Dd8yp8OzQGcajHc3dDhxPHYQpYqizY73xPTQYvtpM7OHO2axJZI2hZReldSf1bvH6EXUc001ofk2QZr");

exports.createStripePaymentIntent = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method Not Allowed");
  }

  try {
    const { amount, currency = "ron", venueId } = req.body;
    
    if (!amount) {
      return res.status(400).send("Missing amount");
    }

    // Convert amount to cents for Stripe (e.g. 10.50 RON -> 1050)
    const amountInCents = Math.round(parseFloat(amount) * 100);

    // Create a PaymentIntent with the order amount and currency
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInCents,
      currency: currency,
      // We accept cards, apple pay, google pay automatically 
      // when using paymentIntents and PaymentSheet on the client
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        venueId: venueId || "unknown",
      }
    });

    res.status(200).json({
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: "", // Usually generated for returning customers
      customer: "" // Usually generated for returning customers
    });
  } catch (error) {
    console.error("Stripe Error:", error);
    res.status(500).json({ error: error.message });
  }
});
