import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../l10n/strings.dart';

/// Rezultatul unei verificări / folosiri de cod de reducere.
class VoucherResult {
  final bool ok;
  final String? reason; // not_found, inactive, expired, not_started, exhausted, already_used, not_new_user, min_amount, too_many_attempts, unavailable
  final double discount;
  final String code;
  final double amount; // prețul mesei pentru care s-a calculat reducerea
  final double minAmount;
  final String? voucherId;
  final String? redemptionId;

  const VoucherResult({
    required this.ok,
    this.reason,
    this.discount = 0,
    this.code = '',
    this.amount = 0,
    this.minAmount = 0,
    this.voucherId,
    this.redemptionId,
  });

  /// Reducerea mai e valabilă pentru prețul curent? (dacă s-a schimbat ora/masa, codul trebuie aplicat din nou)
  bool validFor(double currentAmount) => ok && (amount - currentAmount).abs() < 0.01;

  String get errorMessage {
    switch (reason) {
      case 'min_amount':
        return tr('vc.err_min_amount', {'min': minAmount.toStringAsFixed(0)});
      case 'not_found':
      case 'inactive':
      case 'expired':
      case 'not_started':
      case 'exhausted':
      case 'already_used':
      case 'not_new_user':
      case 'too_many_attempts':
        return tr('vc.err_$reason');
      default:
        return tr('vc.err_unavailable');
    }
  }
}

/// Coduri de reducere (Cloud Functions `checkVoucher` / `redeemVoucher` / `releaseVoucher`).
class VoucherService {
  VoucherService._();

  static const String _base = 'https://us-central1-pingpongplayhub1.cloudfunctions.net';

  static Future<http.Response> _post(String function, Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('not-signed-in');
    final token = await user.getIdToken();
    return http
        .post(
          Uri.parse('$_base/$function'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
  }

  static VoucherResult _parse(http.Response r, double amount) {
    if (r.statusCode != 200) return const VoucherResult(ok: false, reason: 'unavailable');
    final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return VoucherResult(
      ok: m['ok'] == true,
      reason: m['reason']?.toString(),
      discount: ((m['discount'] as num?) ?? 0).toDouble(),
      code: (m['code'] ?? '').toString(),
      amount: amount,
      minAmount: ((m['minAmount'] as num?) ?? 0).toDouble(),
      voucherId: m['voucherId']?.toString(),
      redemptionId: m['redemptionId']?.toString(),
    );
  }

  /// Verifică un cod fără să-l consume (previzualizare).
  static Future<VoucherResult> check({required String venueId, required String code, required double amount}) async {
    try {
      final r = await _post('checkVoucher', {'venueId': venueId, 'code': code, 'amount': amount});
      return _parse(r, amount);
    } catch (_) {
      return const VoucherResult(ok: false, reason: 'unavailable');
    }
  }

  /// Rezervă o folosire a codului (o consumă). Dacă rezervarea nu se finalizează, apelează [release].
  static Future<VoucherResult> redeem({required String venueId, required String code, required double amount}) async {
    try {
      final r = await _post('redeemVoucher', {'venueId': venueId, 'code': code, 'amount': amount});
      return _parse(r, amount);
    } catch (_) {
      return const VoucherResult(ok: false, reason: 'unavailable');
    }
  }

  /// Eliberează o folosire rezervată (plata a eșuat, masa s-a ocupat etc.). Nu aruncă erori.
  static Future<void> release(VoucherResult? redeemed) async {
    if (redeemed == null || redeemed.voucherId == null || redeemed.redemptionId == null) return;
    try {
      await _post('releaseVoucher', {'voucherId': redeemed.voucherId, 'redemptionId': redeemed.redemptionId});
    } catch (_) {}
  }
}
