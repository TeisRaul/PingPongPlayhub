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
    const { amount, currency = "ron", venueId, destinationAccountId } = req.body;
    
    if (!amount) {
      return res.status(400).send("Missing amount");
    }

    // Convert amount to cents for Stripe (e.g. 10.50 RON -> 1050)
    const amountInCents = Math.round(parseFloat(amount) * 100);

    const paymentIntentConfig = {
      amount: amountInCents,
      currency: currency,
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        venueId: venueId || "unknown",
      }
    };

    // If destinationAccountId is provided, we route funds and take 5 RON fee
    if (destinationAccountId) {
      paymentIntentConfig.transfer_data = {
        destination: destinationAccountId,
      };
      // The platform fee is 5 RON = 500 bani
      paymentIntentConfig.application_fee_amount = 500;
    }

    // Create a PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create(paymentIntentConfig);

    res.status(200).json({
      paymentIntent: paymentIntent.client_secret,
      ephemeralKey: "",
      customer: ""
    });
  } catch (error) {
    console.error("Stripe Error:", error);
    res.status(500).json({ error: error.message });
  }
});

exports.createStripeConnectAccount = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  
  try {
    const { email } = req.body;
    const account = await stripe.accounts.create({
      type: 'express',
      email: email,
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
    });

    res.status(200).json({ accountId: account.id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

exports.createStripeAccountLink = onRequest({cors: true}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");
  
  try {
    const { accountId } = req.body;
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: 'https://pingpongplayhub.web.app/reauth', // placeholders
      return_url: 'https://pingpongplayhub.web.app/return',
      type: 'account_onboarding',
    });

    res.status(200).json({ url: accountLink.url });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
