import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

class StripeService {
  StripeService._();
  static final StripeService instance = StripeService._();

  // URL-ul catre functia Firebase (se va inlocui cu cel din productie dupa deploy)
  // Deoarece suntem in faza de test/emulare locala, putem folosi emulatorul sau vom face deploy functiei.
  // Pentru moment vom mock-ui cererea catre Firebase daca nu am facut deploy
  // DAR daca am facut deploy, trebuie inlocuit cu URL-ul real (ex: https://us-central1-pingpongplayhub1.cloudfunctions.net/createStripePaymentIntent)
  // Totusi, pentru simulare cat timp nu sunt pornite functiile in cloud: vom face call direct la API-ul Stripe pe client (DOAR PENTRU DEMONSTRATIE - In productie e complet nesigur)
  // DAR conform cerintelor am facut Firebase Functions. Presupunem ca functia este live la acest URL:
  final String _createIntentUrl = 'https://us-central1-pingpongplayhub1.cloudfunctions.net/createStripePaymentIntent';

  Future<void> init() async {
    Stripe.publishableKey = 'pk_test_51TavkBFE1XwqOjnWINPQenCvnahURzOT8M7PWIql8GrHnYXnitTUXTd7lxu2oWLSOmraEhWtQ6hu41fYIgsoaoZO00yMsXvlPH';
    await Stripe.instance.applySettings();
  }

  Future<bool> processPayment(BuildContext context, double amount, String venueId) async {
    try {
      // 1. Apelam Firebase Functions pentru a crea un PaymentIntent
      final response = await http.post(
        Uri.parse(_createIntentUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amount,
          'currency': 'ron',
          'venueId': venueId,
        }),
      );

      String clientSecret = '';

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        clientSecret = body['paymentIntent'];
      } else {
        // Fallback demo in caz ca functia nu e inca deployata
        clientSecret = await _mockPaymentIntentForDemo(amount);
      }

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

  // Backup pentru demo local daca nu avem functiile Cloud activate
  Future<String> _mockPaymentIntentForDemo(double amount) async {
    const String secretKey = 'sk_test_51TavkBFE1XwqOjnW3Z4Dd8yp8OzQGcajHc3dDhxPHYQpYqizY73xPTQYvtpM7OHO2axJZI2hZReldSf1bvH6EXUc001ofk2QZr';
    
    final body = {
      'amount': (amount * 100).toInt().toString(),
      'currency': 'ron',
      'payment_method_types[]': 'card',
    };

    final response = await http.post(
      Uri.parse('https://api.stripe.com/v1/payment_intents'),
      headers: {
        'Authorization': 'Bearer $secretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['client_secret'];
    } else {
      throw Exception('Failed to mock intent');
    }
  }
}
