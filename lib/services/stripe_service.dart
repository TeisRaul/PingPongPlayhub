import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

class StripeService {
  StripeService._();
  static final StripeService instance = StripeService._();

  // Functia Cloud care creeaza PaymentIntent-ul (cere utilizator autentificat).
  final String _createIntentUrl = 'https://us-central1-pingpongplayhub1.cloudfunctions.net/createStripePaymentIntent';

  Future<void> init() async {
    Stripe.publishableKey = 'pk_test_51TavkBFE1XwqOjnWINPQenCvnahURzOT8M7PWIql8GrHnYXnitTUXTd7lxu2oWLSOmraEhWtQ6hu41fYIgsoaoZO00yMsXvlPH';
    await Stripe.instance.applySettings();
  }

  Future<bool> processPayment(BuildContext context, double amount, String venueId, {String? destinationAccountId}) async {
    try {
      // 1. Apelam Firebase Functions pentru a crea un PaymentIntent
      final bodyData = {
        'amount': amount,
        'currency': 'ron',
        'venueId': venueId,
      };

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Trebuie să fii autentificat pentru a plăti.');
      }
      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse(_createIntentUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(bodyData),
      );

      if (response.statusCode != 200) {
        throw Exception('Nu s-a putut inițializa plata (${response.statusCode}).');
      }
      final String clientSecret = jsonDecode(response.body)['paymentIntent'];

      // 2. Initializam Payment Sheet cu butoanele de Apple/Google Pay activate automat
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'PingPong Playhub',
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'RO',
            testEnv: true,
          ),
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'RO',
          ),
          style: ThemeMode.dark,
        ),
      );

      // 3. Prezentam Payment Sheet utilizatorului
      await Stripe.instance.presentPaymentSheet();

      // Daca codul a ajuns aici fara eroare, plata este cu succes
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plata a fost procesată cu succes!'),
            backgroundColor: Color(0xFF00FF66),
          ),
        );
      }
      return true;
    } on StripeException catch (e) {
      debugPrint('Stripe Error: ${e.error.localizedMessage}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.error.localizedMessage ?? 'Plata a fost anulată sau a eșuat.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('Payment Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A apărut o eroare la inițializarea plății.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }
  }
}
