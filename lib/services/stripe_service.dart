import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'pay_window.dart';

class StripeService {
  StripeService._();
  static final StripeService instance = StripeService._();

  static const String _functionsBase = 'https://us-central1-pingpongplayhub1.cloudfunctions.net';

  // Funcția Cloud care creează PaymentIntent-ul (Android/iOS; cere utilizator autentificat).
  final String _createIntentUrl = '$_functionsBase/createStripePaymentIntent';
  // Versiunea web: pagina Stripe Checkout + verificarea plății.
  final String _createCheckoutUrl = '$_functionsBase/createBookingCheckout';
  final String _checkoutStatusUrl = '$_functionsBase/getCheckoutStatus';

  Future<void> init() async {
    Stripe.publishableKey = 'pk_test_51TavkBFE1XwqOjnWINPQenCvnahURzOT8M7PWIql8GrHnYXnitTUXTd7lxu2oWLSOmraEhWtQ6hu41fYIgsoaoZO00yMsXvlPH';
    await Stripe.instance.applySettings();
  }

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('not-signed-in');
    }
    final token = await user.getIdToken();
    if (token == null) throw Exception('no-token');
    return token;
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _idToken()}',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('http-${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  void _snack(BuildContext context, String text, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  /// [purpose] spune serverului ce se plătește: {'kind': 'booking', 'matchId': ...} pentru o rezervare
  /// deja creată (în așteptarea plății) sau {'kind': 'pass', ...} pentru un abonament de sală.
  /// Confirmarea finală o face serverul, prin webhook-ul Stripe.
  Future<bool> processPayment(BuildContext context, double amount, String venueId,
      {String? destinationAccountId, Map<String, dynamic>? purpose}) async {
    if (kIsWeb) return _processWeb(context, amount, venueId, purpose);

    try {
      // 1. Funcția Cloud creează PaymentIntent-ul (contul sălii se citește pe server).
      final data = await _post(_createIntentUrl, {
        'amount': amount,
        'currency': 'ron',
        'venueId': venueId,
        if (purpose != null) 'purpose': purpose,
      });
      final String clientSecret = data['paymentIntent'];

      // 2. Fereastra de plată Stripe, cu Google Pay / Apple Pay când sunt disponibile.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Playhub',
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

      // 3. Dacă se întoarce fără eroare, plata a reușit.
      await Stripe.instance.presentPaymentSheet();

      if (context.mounted) _snack(context, tr('pay.success'), AppColors.good);
      return true;
    } on StripeException catch (e) {
      debugPrint('Stripe Error: ${e.error.localizedMessage}');
      if (context.mounted) {
        _snack(context, e.error.localizedMessage ?? tr('pay.cancelled'), Colors.redAccent);
      }
      return false;
    } catch (e) {
      debugPrint('Payment Error: $e');
      if (context.mounted) _snack(context, tr('pay.init_error'), Colors.redAccent);
      return false;
    }
  }

  /// Web: pagina Stripe Checkout se deschide într-o fereastră nouă, iar aplicația așteaptă
  /// confirmarea plății (verifică la câteva secunde). Datele cardului rămân doar la Stripe.
  Future<bool> _processWeb(BuildContext context, double amount, String venueId, Map<String, dynamic>? purpose) async {
    // Fereastra se deschide acum, cât suntem încă în click-ul utilizatorului (altfel e blocată).
    final PayWindow? window = PayWindow.openBlank();
    try {
      final data = await _post(_createCheckoutUrl, {
        'amount': amount,
        'venueId': venueId,
        if (purpose != null) 'purpose': purpose,
      });
      final String id = data['id'];
      final String url = data['url'];
      window?.go(url);
      if (!context.mounted) {
        window?.close();
        return false;
      }
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CheckoutWaitDialog(
          url: url,
          window: window,
          checkStatus: ({bool cancel = false}) => checkoutStatus(id, cancel: cancel),
        ),
      );
      if (paid == true) {
        if (context.mounted) _snack(context, tr('pay.success'), AppColors.good);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Checkout Error: $e');
      window?.close();
      if (context.mounted) _snack(context, tr('pay.init_error'), Colors.redAccent);
      return false;
    }
  }

  /// "paid", "open" sau "expired". Cu [cancel], o sesiune încă neplătită este închisă.
  Future<String> checkoutStatus(String sessionId, {bool cancel = false}) async {
    final data = await _post(_checkoutStatusUrl, {'id': sessionId, if (cancel) 'cancel': true});
    return (data['status'] ?? 'open').toString();
  }
}

class _CheckoutWaitDialog extends StatefulWidget {
  const _CheckoutWaitDialog({required this.url, required this.window, required this.checkStatus});

  final String url;
  final PayWindow? window;
  final Future<String> Function({bool cancel}) checkStatus;

  @override
  State<_CheckoutWaitDialog> createState() => _CheckoutWaitDialogState();
}

class _CheckoutWaitDialogState extends State<_CheckoutWaitDialog> {
  static const _interval = Duration(seconds: 3);
  static const _maxWait = Duration(minutes: 30);

  Timer? _timer;
  PayWindow? _window;
  bool _checking = false;
  bool _closing = false;
  bool _expired = false;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _window = widget.window;
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_checking || _closing) return;
    if (DateTime.now().difference(_startedAt) > _maxWait) {
      await _cancel();
      return;
    }
    _checking = true;
    try {
      final status = await widget.checkStatus();
      if (!mounted || _closing) return;
      if (status == 'paid') {
        _finish(true);
      } else if (status == 'expired') {
        _timer?.cancel();
        setState(() => _expired = true);
      }
    } catch (_) {
      // Eroare de rețea trecătoare: încercăm din nou la următorul pas.
    } finally {
      _checking = false;
    }
  }

  void _finish(bool paid) {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _window?.close();
    if (mounted) Navigator.of(context).pop(paid);
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _timer?.cancel();
    var paid = false;
    try {
      // Închidem sesiunea Stripe; dacă tocmai s-a plătit, răspunsul e "paid" și păstrăm rezervarea.
      paid = await widget.checkStatus(cancel: true) == 'paid';
    } catch (_) {}
    _finish(paid);
  }

  void _reopen() {
    _window = PayWindow.open(widget.url) ?? _window;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(tr('pay.web_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _expired ? tr('pay.web_expired') : tr('pay.web_body'),
            style: TextStyle(color: AppColors.text70, height: 1.4),
          ),
          if (widget.window == null && !_expired) ...[
            const SizedBox(height: 10),
            Text(tr('pay.web_blocked'), style: TextStyle(color: AppColors.gold, fontSize: 13, height: 1.3)),
          ],
          if (!_expired) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('pay.web_waiting'), style: TextStyle(color: AppColors.muted, fontSize: 13))),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : (_expired ? () => _finish(false) : _cancel),
          child: Text(tr('pay.web_cancel'), style: TextStyle(color: AppColors.muted)),
        ),
        if (!_expired)
          ElevatedButton(
            onPressed: _closing ? null : _reopen,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
            child: Text(tr('pay.web_open')),
          ),
      ],
    );
  }
}
