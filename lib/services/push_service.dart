import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/notifications_screen.dart';
import '../widgets/notification_popups.dart';

/// Notificări push (Firebase Cloud Messaging).
/// Token-ul dispozitivului se salvează în `push_tokens/{token}`; Cloud Function-ul `sendPushNotification`
/// trimite câte un push pentru fiecare document nou din `notifications`.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const String _askedKey = 'push_asked';
  static const String _offKey = 'push_off';

  bool _wired = false;
  String? _token;

  /// FCM nu există pe Windows / Linux.
  bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  bool _granted(AuthorizationStatus s) =>
      s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

  /// Permisiunea e dată și utilizatorul nu a oprit notificările din aplicație.
  Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final prefs = await _prefs();
      if (prefs?.getBool(_offKey) == true) return false;
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return _granted(s.authorizationStatus);
    } catch (_) {
      return false;
    }
  }

  /// Pornește notificările push pe acest dispozitiv. Întoarce `false` dacă permisiunea e refuzată.
  Future<bool> enable({bool ask = true}) async {
    if (!supported || FirebaseAuth.instance.currentUser == null) return false;
    try {
      final messaging = FirebaseMessaging.instance;
      var settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined && ask) {
        settings = await messaging.requestPermission();
      }
      if (!_granted(settings.authorizationStatus)) return false;

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return false;
      await _save(token);
      (await _prefs())?.setBool(_offKey, false);
      _wire();
      return true;
    } catch (e) {
      debugPrint('Push enable error: $e');
      return false;
    }
  }

  /// Oprește notificările push pe acest dispozitiv.
  Future<void> disable() async {
    (await _prefs())?.setBool(_offKey, true);
    await _removeToken();
  }

  /// La autentificare: reînnoiește token-ul dacă permisiunea e deja dată; pe mobil cere permisiunea o dată.
  Future<void> onLogin() async {
    if (!supported) return;
    try {
      final prefs = await _prefs();
      if (prefs?.getBool(_offKey) == true) return;
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (_granted(settings.authorizationStatus)) {
        await enable(ask: false);
      } else if (!kIsWeb &&
          settings.authorizationStatus == AuthorizationStatus.notDetermined &&
          prefs?.getBool(_askedKey) != true) {
        await prefs?.setBool(_askedKey, true);
        await enable(ask: true);
      }
    } catch (e) {
      debugPrint('Push onLogin error: $e');
    }
  }

  /// La deconectare: acest dispozitiv nu mai primește notificările contului.
  Future<void> onLogout() async {
    if (!supported) return;
    await _removeToken();
  }

  Future<void> _save(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _token = token;
    await FirebaseFirestore.instance.collection('push_tokens').doc(token).set({
      'uid': user.uid,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _removeToken() async {
    try {
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
        await FirebaseFirestore.instance.collection('push_tokens').doc(token).delete();
      }
      _token = null;
    } catch (e) {
      debugPrint('Push removeToken error: $e');
    }
  }

  void _wire() {
    if (_wired) return;
    _wired = true;
    final messaging = FirebaseMessaging.instance;
    messaging.onTokenRefresh.listen((t) => _save(t));
    // Atingere pe notificare: deschide lista de notificări.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());
    messaging.getInitialMessage().then((m) {
      if (m != null) Future.delayed(const Duration(seconds: 1), _openNotifications);
    });
  }

  void _openNotifications() {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) NotificationsDialog.show(ctx);
  }
}
