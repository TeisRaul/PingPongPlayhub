import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'l10n/app_locales.dart';
import 'theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart';
import 'firebase_options.dart';

import 'services/stripe_service.dart';
import 'services/deep_link_service.dart';
import 'services/share_service.dart';
import 'widgets/notification_popups.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limba implicită până se loghează utilizatorul = limba telefonului (dacă e suportată).
  await initializeDateFormatting();
  AppLocales.apply(AppLocales.deviceDefault());
  await AppLocales.loadLocal(); // limba aleasă data trecută pe acest dispozitiv
  await ThemeController.load(); // tema aleasă data trecută (luminoasă / întunecată / sistem)
  
  // NOTE: You must have Firebase configured (firebase_options.dart / google-services.json).
  // I am disabling this temporarily so you can see the UI without white screens!
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("Eroare Firebase: $e");
  }
  
  // Plata cu cardul (Stripe) funcționează doar pe mobil; pe web plugin-ul nu există.
  if (!kIsWeb) {
    try {
      await StripeService.instance.init();
    } catch (e) {
      print("Eroare Stripe init: $e");
    }
  }
  
  ShareService.captureInitialWebLink(); // link de meci deschis în browser
  DeepLinkService.instance.init();
  NotificationPopups.instance.init(); // popup în timp real pentru notificări noi
  
  runApp(const PingPongPlayhubApp());
}

class PingPongPlayhubApp extends StatelessWidget {
  const PingPongPlayhubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) => ValueListenableBuilder<String>(
      valueListenable: AppLocales.current,
      builder: (context, languageCode, _) => MaterialApp(
      title: 'Playhub',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      locale: AppLocales.locale,
      supportedLocales: [for (final l in AppLocales.languages) l.locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeSync(child: child ?? const SizedBox.shrink()),
      home: const LoginScreen(),
      ),
      ),
    );
  }
}
