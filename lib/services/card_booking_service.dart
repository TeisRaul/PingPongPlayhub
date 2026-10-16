import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Eroare la renunțare / anulare (mesajul vine de la server, ex. „Match already started").
class CardBookingException implements Exception {
  CardBookingException(this.code, this.status);
  final String code;
  final int status;

  bool get alreadyStarted => code.contains('started');

  @override
  String toString() => 'CardBookingException($status, $code)';
}

/// Rezervări plătite cu cardul: plata împărțită și renunțarea / anularea cu rambursare.
/// Banii se întorc prin Stripe, de pe server (funcția cancelCardBooking).
class CardBookingService {
  CardBookingService._();

  static const double platformFee = 5.0;
  static const double minShare = 2.0; // Stripe nu acceptă plăți mai mici de 2 RON
  static const String _cancelUrl = 'https://us-central1-pingpongplayhub1.cloudfunctions.net/cancelCardBooking';

  static bool isCard(Map<String, dynamic> m) => (m['paymentMethod'] ?? '').toString().contains('Card');

  /// Plătită cu cardul și confirmată de Stripe (deci renunțarea / anularea trece prin server).
  static bool isCardPaid(Map<String, dynamic> m) => isCard(m) && m['paymentStatus'] == 'confirmed';

  static bool isSplit(Map<String, dynamic> m) => m['paymentMode'] == 'split';

  static double _round2(double x) => (x * 100).round() / 100;

  /// Partea fiecărui jucător. La card: (preț + taxa platformei) / locuri; la cash: preț / locuri.
  static double shareAmount(Map<String, dynamic> m) {
    final stored = (m['shareAmount'] as num?)?.toDouble();
    if (stored != null && stored > 0) return _round2(stored);
    final seats = (m['maxPlayers'] as num?)?.toInt() ?? 0;
    if (seats < 2) return 0;
    final price = (m['price'] as num?)?.toDouble() ?? 0;
    return _round2((price + (isCard(m) ? platformFee : 0)) / seats);
  }

  /// Aceeași formulă, pentru ecranul de creare (înainte să existe rezervarea).
  static double previewShare({required double price, required int seats, required bool card}) {
    if (seats < 2) return 0;
    return _round2((price + (card ? platformFee : 0)) / seats);
  }

  static Map<String, dynamic> _payments(Map<String, dynamic> m) =>
      Map<String, dynamic>.from((m['cardPayments'] as Map?) ?? const {});

  /// Cât a plătit (și nu i s-a returnat) jucătorul cu cardul pentru această rezervare.
  static double paidBy(Map<String, dynamic> m, String uid) {
    final p = _payments(m)[uid];
    if (p is! Map) {
      // Rezervări mai vechi, fără registru: gazda a plătit integral.
      if (uid == m['hostUid'] && isCardPaid(m)) {
        return ((m['paidAmount'] ?? m['price']) as num?)?.toDouble() ?? 0;
      }
      return 0;
    }
    final amount = (p['amount'] as num?)?.toDouble() ?? 0;
    final refunded = (p['refunded'] as num?)?.toDouble() ?? 0;
    final left = amount - refunded;
    return left > 0 ? _round2(left) : 0;
  }

  static bool hasPaidShare(Map<String, dynamic> m, String uid) => paidBy(m, uid) > 0;

  /// Câți jucători (în afară de gazdă) și-au plătit partea.
  static int sharesPaid(Map<String, dynamic> m) {
    final joined = List<dynamic>.from(m['joinedUids'] ?? const []);
    return joined.where((u) => u != m['hostUid'] && hasPaidShare(m, u.toString())).length;
  }

  /// Jucătorul trebuie să-și plătească partea (rezervare împărțită, plătită de gazdă, neîncepută).
  static bool owesShare(Map<String, dynamic> m, String uid) {
    final joined = List<dynamic>.from(m['joinedUids'] ?? const []);
    return isSplit(m) &&
        isCardPaid(m) &&
        m['status'] != 'cancelled' &&
        uid != m['hostUid'] &&
        joined.contains(uid) &&
        !hasPaidShare(m, uid) &&
        shareAmount(m) >= minShare;
  }

  /// action: 'leave' (jucător iese și primește partea înapoi) sau 'cancel' (gazda / sala anulează, toți
  /// primesc banii înapoi). Întoarce suma returnată celui care a cerut.
  /// [silent]: sala / adminul trimit ei anunțul de anulare (cu motiv), deci serverul nu-l mai trimite.
  static Future<double> cancel(String matchId, String action, {bool silent = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw CardBookingException('not-signed-in', 401);
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse(_cancelUrl),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'matchId': matchId, 'action': action, if (silent) 'silent': true}),
    );
    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {}
    if (response.statusCode != 200) {
      throw CardBookingException((body['error'] ?? 'http-${response.statusCode}').toString(), response.statusCode);
    }
    return (body['refunded'] as num?)?.toDouble() ?? 0;
  }
}
