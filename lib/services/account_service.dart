import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Export de date și ștergere de cont (Cloud Functions `exportMyData` / `deleteMyAccount`).
class AccountService {
  AccountService._();

  static const String _base = 'https://us-central1-pingpongplayhub1.cloudfunctions.net';

  static Future<http.Response> _post(String function, Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('not-signed-in');
    final token = await user.getIdToken(true);
    return http.post(
      Uri.parse('$_base/$function'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
  }

  /// Toate datele utilizatorului, ca JSON formatat.
  static Future<String> exportData() async {
    final response = await _post('exportMyData', {});
    if (response.statusCode != 200) throw Exception('export-${response.statusCode}');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// Șterge contul. Întoarce `false` dacă serverul a refuzat (ex. cont de administrator).
  static Future<bool> deleteAccount() async {
    final response = await _post('deleteMyAccount', {'confirm': true});
    if (response.statusCode == 403) return false;
    if (response.statusCode != 200) throw Exception('delete-${response.statusCode}');
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // contul nu mai există; sesiunea locală se închide oricum
    }
    return true;
  }
}
