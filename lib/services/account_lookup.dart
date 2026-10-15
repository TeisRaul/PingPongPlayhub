import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Căutări publice minimale, folosite ÎNAINTE de autentificare:
/// - autentificare cu numele de utilizator → emailul contului;
/// - la înregistrare: este numele / telefonul deja folosit?
///
/// Colecția `users` poate fi citită doar de utilizatori autentificați, așa că aici stau
/// două colecții mici, citibile doar document cu document (fără listare):
///   username_lookup/{username cu litere mici} → {uid, email, username}
///   phone_lookup/{telefon fără spații}        → {uid}
class AccountLookup {
  AccountLookup._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String usernameKey(String username) => username.trim().toLowerCase().replaceAll('/', '_');
  static String phoneKey(String phone) => phone.replaceAll(RegExp(r'\s+'), '').replaceAll('/', '_');

  /// Emailul contului cu acest nume de utilizator (null dacă nu există).
  static Future<String?> emailForUsername(String username) async {
    final key = usernameKey(username);
    if (key.isEmpty) return null;
    final snap = await _db.collection('username_lookup').doc(key).get();
    final email = snap.data()?['email'];
    return email is String && email.isNotEmpty ? email : null;
  }

  static Future<bool> usernameTaken(String username, {String? exceptUid}) async {
    final key = usernameKey(username);
    if (key.isEmpty) return false;
    final snap = await _db.collection('username_lookup').doc(key).get();
    if (!snap.exists) return false;
    return snap.data()?['uid'] != exceptUid;
  }

  static Future<bool> phoneTaken(String phone, {String? exceptUid}) async {
    final key = phoneKey(phone);
    if (key.isEmpty) return false;
    final snap = await _db.collection('phone_lookup').doc(key).get();
    if (!snap.exists) return false;
    return snap.data()?['uid'] != exceptUid;
  }

  /// Scrie (sau mută) înregistrările de căutare ale utilizatorului curent.
  static Future<void> sync({
    required String uid,
    required String username,
    required String email,
    required String phone,
    String? oldUsername,
    String? oldPhone,
  }) async {
    if (username.trim().isNotEmpty) {
      await _db.collection('username_lookup').doc(usernameKey(username)).set({
        'uid': uid,
        'email': email,
        'username': username.trim(),
      });
    }
    if (phone.trim().isNotEmpty) {
      await _db.collection('phone_lookup').doc(phoneKey(phone)).set({'uid': uid});
    }
    if (oldUsername != null && oldUsername.trim().isNotEmpty && usernameKey(oldUsername) != usernameKey(username)) {
      try {
        await _db.collection('username_lookup').doc(usernameKey(oldUsername)).delete();
      } catch (_) {}
    }
    if (oldPhone != null && oldPhone.trim().isNotEmpty && phoneKey(oldPhone) != phoneKey(phone)) {
      try {
        await _db.collection('phone_lookup').doc(phoneKey(oldPhone)).delete();
      } catch (_) {}
    }
  }

  /// Conturile create înainte de această funcție nu au înregistrări de căutare.
  /// La prima conectare (cu email) sau la deschiderea aplicației, se completează automat.
  static Future<void> ensureForCurrentUser() async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return;
      final doc = await _db.collection('users').doc(me.uid).get();
      final d = doc.data();
      if (d == null) return;
      final username = (d['username'] ?? '').toString();
      final phone = (d['phone'] ?? '').toString();
      final email = (d['email'] ?? me.email ?? '').toString();
      final uKey = usernameKey(username);
      if (uKey.isNotEmpty) {
        final u = await _db.collection('username_lookup').doc(uKey).get();
        if (!u.exists) {
          await _db.collection('username_lookup').doc(uKey).set({'uid': me.uid, 'email': email, 'username': username.trim()});
        }
      }
      final pKey = phoneKey(phone);
      if (pKey.isNotEmpty) {
        final p = await _db.collection('phone_lookup').doc(pKey).get();
        if (!p.exists) {
          await _db.collection('phone_lookup').doc(pKey).set({'uid': me.uid});
        }
      }
    } catch (_) {
      // Nu blocăm aplicația dacă nu reușește.
    }
  }
}
