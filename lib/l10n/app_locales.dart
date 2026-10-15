import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O limbă pe care o poate alege utilizatorul.
class AppLanguage {
  final String code; // salvat în Firestore (users/venues .language)
  final Locale locale;
  final String name; // numele în limba respectivă
  final String tag; // etichetă scurtă afișată în listă

  const AppLanguage(this.code, this.locale, this.name, this.tag);
}

/// Limba curentă a aplicației + salvarea ei pe contul utilizatorului.
class AppLocales {
  AppLocales._();

  static const String fallbackCode = 'ro';

  static const List<AppLanguage> languages = [
    AppLanguage('en_US', Locale('en', 'US'), 'English (US)', 'EN-US'),
    AppLanguage('en_GB', Locale('en', 'GB'), 'English (UK)', 'EN-UK'),
    AppLanguage('ro', Locale('ro'), 'Română', 'RO'),
    AppLanguage('fr', Locale('fr'), 'Français', 'FR'),
    AppLanguage('es', Locale('es'), 'Español', 'ES'),
    AppLanguage('hu', Locale('hu'), 'Magyar', 'HU'),
  ];

  /// Codul limbii curente; MaterialApp ascultă acest notifier.
  static final ValueNotifier<String> current = ValueNotifier<String>(fallbackCode);

  static bool isSupported(String? code) => languages.any((l) => l.code == code);

  static AppLanguage byCode(String? code) {
    for (final l in languages) {
      if (l.code == code) return l;
    }
    return languages.firstWhere((l) => l.code == fallbackCode);
  }

  static Locale get locale => byCode(current.value).locale;

  /// Limba telefonului dacă e printre cele suportate, altfel română.
  static String deviceDefault() {
    final l = WidgetsBinding.instance.platformDispatcher.locale;
    if (l.languageCode == 'en') return l.countryCode == 'GB' ? 'en_GB' : 'en_US';
    for (final lang in languages) {
      if (lang.locale.languageCode == l.languageCode) return lang.code;
    }
    return fallbackCode;
  }

  static const String _prefKey = 'app_language';

  /// true dacă utilizatorul a ales limba pe ecranele de dinainte de autentificare (în această rulare).
  /// Atunci alegerea lui are prioritate față de limba salvată pe cont și se salvează pe cont.
  static bool chosenBeforeLogin = false;

  /// Limba aleasă data trecută pe acest dispozitiv (dacă există) devine limba curentă.
  static Future<void> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? code = prefs.getString(_prefKey);
      if (isSupported(code)) apply(code);
    } catch (_) {}
  }

  static Future<void> saveLocal(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }

  /// Alegerea limbii din ecranele de dinainte de cont (login, înregistrare).
  static Future<void> chooseBeforeLogin(String code) async {
    apply(code);
    chosenBeforeLogin = true;
    await saveLocal(code);
  }

  /// Aplică limba în aplicație (nu o salvează).
  static void apply(String? code) {
    final String safe = isSupported(code) ? code! : fallbackCode;
    Intl.defaultLocale = safe;
    current.value = safe;
  }

  /// Salvează alegerea pe documentul utilizatorului (jucător sau sală).
  static Future<void> saveForCurrentUser(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!isSupported(code)) return;
    await saveLocal(code);
    if (user == null) return;
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(user.uid);
    if ((await userRef.get()).exists) {
      await userRef.set({'language': code}, SetOptions(merge: true));
      return;
    }
    final venueRef = db.collection('venues').doc(user.uid);
    if ((await venueRef.get()).exists) {
      await venueRef.set({'language': code}, SetOptions(merge: true));
    }
  }
}
