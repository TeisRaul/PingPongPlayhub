import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Abonamentul lunar al sălilor (100 RON / lună, încasat prin Stripe Billing).
/// Starea abonamentului stă în `venues/{id}.billing` și o scrie doar Cloud Function-ul `stripeWebhook`
/// (sau adminul, pentru perioade acordate manual).
class BillingService {
  BillingService._();

  static const String _base = 'https://us-central1-pingpongplayhub1.cloudfunctions.net';
  static const double monthlyPriceRon = 100;

  static Future<String> _postForUrl(String function) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Trebuie să fii autentificat.');
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_base/$function'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({}),
    );
    if (response.statusCode != 200) {
      throw Exception('Cerere eșuată (${response.statusCode}).');
    }
    final url = jsonDecode(response.body)['url'];
    if (url is! String || url.isEmpty) throw Exception('Răspuns invalid de la server.');
    return url;
  }

  static Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) throw Exception('Nu am putut deschide pagina de plată.');
  }

  /// Deschide pagina Stripe unde sala plătește abonamentul.
  static Future<void> startCheckout() async => _open(await _postForUrl('createVenueSubscriptionCheckout'));

  /// Portalul Stripe: schimbare card, facturi, anulare.
  static Future<void> openPortal() async => _open(await _postForUrl('createVenueBillingPortal'));

  static Map<String, dynamic> _billing(Map<String, dynamic>? venue) {
    final b = venue?['billing'];
    return b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{};
  }

  static DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

  /// Până când e acordat manual (de admin), dacă e cazul.
  static DateTime? manualUntil(Map<String, dynamic>? venue) => _date(_billing(venue)['manualUntil']);

  static DateTime? periodEnd(Map<String, dynamic>? venue) => _date(_billing(venue)['currentPeriodEnd']);

  static String status(Map<String, dynamic>? venue) => (_billing(venue)['status'] ?? '').toString();

  /// Abonamentul e valid acum? (activ, sau plată întârziată în perioada de grație Stripe, sau acordat manual.)
  static bool isActive(Map<String, dynamic>? venue, {DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    final DateTime? manual = manualUntil(venue);
    if (manual != null && manual.isAfter(t)) return true;
    final s = status(venue);
    return s == 'active' || s == 'trialing' || s == 'past_due';
  }

  /// Adminul a făcut abonamentul obligatoriu? (`config/billing.subscriptionRequired`)
  static Future<bool> subscriptionRequired() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('config').doc('billing').get();
      return snap.data()?['subscriptionRequired'] == true;
    } catch (_) {
      return false; // dacă nu putem citi setarea, nu ascundem săli
    }
  }

  /// Sala se afișează jucătorilor? Locațiile publice (gratuite) nu au abonament.
  static bool venueVisible(Map<String, dynamic> venue, bool required) {
    if (!required) return true;
    if (venue['isPublic'] == true) return true;
    return isActive(venue);
  }
}
