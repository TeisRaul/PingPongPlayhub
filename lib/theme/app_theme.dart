import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Culorile aplicației. Valorile se schimbă după tema activă (întunecată / luminoasă).
/// Se folosesc în loc de `Color(0xFF...)` / `Colors.white` / `Colors.grey` hardcodate.
class AppColors {
  AppColors._();

  /// Setat din [ThemeSync] la fiecare build al aplicației.
  static bool dark = true;

  static Color _c(Color d, Color l) => dark ? d : l;

  // Fundaluri
  static Color get bg => _c(const Color(0xFF0A0E17), const Color(0xFFF3F6FA));
  static Color get bgDeep => _c(const Color(0xFF0D1424), const Color(0xFFE9EEF5));
  static Color get card => _c(const Color(0xFF131A2A), const Color(0xFFFFFFFF));
  static Color get card2 => _c(const Color(0xFF1E293B), const Color(0xFFE8EDF4));
  static Color get card3 => _c(const Color(0xFF1A2A3A), const Color(0xFFEEF2F7));

  // Accent (singura culoare de brand)
  static Color get accent => _c(const Color(0xFF00E5FF), const Color(0xFF0A7D99));
  static Color get accent2 => _c(const Color(0xFF00B8D4), const Color(0xFF0E6A82));
  static Color get onAccent => _c(Colors.black, Colors.white);

  // Culori de stare (doar pentru status: reușit / eroare / atenție)
  static Color get good => _c(const Color(0xFF00FF66), const Color(0xFF15803D));
  static Color get bad => _c(const Color(0xFFFF0055), const Color(0xFFE11D48));
  static Color get gold => _c(const Color(0xFFFFD700), const Color(0xFFB7791F));

  // Text
  static Color get text => _c(Colors.white, const Color(0xFF0F172A));
  static Color get text70 => _c(Colors.white70, const Color(0xFF475569));
  static Color get text54 => _c(Colors.white54, const Color(0xFF64748B));
  static Color get text38 => _c(Colors.white38, const Color(0xFF94A3B8));
  static Color get text24 => _c(Colors.white24, const Color(0x3D0F172A));
  static Color get text12 => _c(Colors.white12, const Color(0x1F0F172A));
  static Color get text10 => _c(Colors.white10, const Color(0x190F172A));
  static Color get muted => _c(const Color(0xFFA9B1BF), const Color(0xFF64748B));
  static Color get muted2 => _c(const Color(0xFF7C8594), const Color(0xFF8492A6));

  /// Schema de culori pentru ferestrele de selecție (dată/oră), după tema activă.
  static ColorScheme scheme({
    required Color primary,
    required Color onPrimary,
    required Color surface,
    required Color onSurface,
  }) {
    return dark
        ? ColorScheme.dark(primary: primary, onPrimary: onPrimary, surface: surface, onSurface: onSurface)
        : ColorScheme.light(primary: primary, onPrimary: onPrimary, surface: surface, onSurface: onSurface);
  }

  // Borduri / separatoare
  static Color get border => _c(const Color(0xFF424242), const Color(0xFFCBD5E1));
  static Color get border700 => _c(const Color(0xFF616161), const Color(0xFFB6C2D2));
}

/// Tema aleasă de utilizator: luminoasă, întunecată sau a sistemului. Se ține minte pe dispozitiv.
class ThemeController {
  ThemeController._();

  static const String _prefKey = 'app_theme';
  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _parse(prefs.getString(_prefKey));
    } catch (_) {
      // rămâne tema implicită
    }
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, m.name);
    } catch (_) {
      // nu e grav dacă nu se poate salva
    }
  }

  static ThemeMode _parse(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF00E5FF),
      scaffoldBackgroundColor: const Color(0xFF0A0E17),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        secondary: Color(0xFF00B8D4),
        surface: Color(0xFF131A2A),
      ),
      fontFamily: 'Inter',
      useMaterial3: true,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF131A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIconColor: Colors.grey,
      ),
    );
  }

  static ThemeData light() {
    const accent = Color(0xFF0A7D99);
    const bg = Color(0xFFF3F6FA);
    const card = Color(0xFFFFFFFF);
    const text = Color(0xFF0F172A);
    const muted = Color(0xFF64748B);
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: accent,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: Color(0xFF0E6A82),
        surface: card,
        onSurface: text,
        surfaceTint: Colors.transparent,
      ),
      fontFamily: 'Inter',
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      popupMenuTheme: const PopupMenuThemeData(color: card, surfaceTintColor: Colors.transparent),
      drawerTheme: const DrawerThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      dividerTheme: const DividerThemeData(color: Color(0xFFCBD5E1)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        labelStyle: const TextStyle(color: muted),
        prefixIconColor: muted,
      ),
    );
  }

  /// Marchează toată aplicația ca "murdară" ca să-și recitească culorile din [AppColors].
  static void rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    });
  }
}

/// Pus în `MaterialApp.builder`: ține [AppColors.dark] la zi și reface ecranele când se schimbă tema.
class ThemeSync extends StatefulWidget {
  final Widget child;
  const ThemeSync({super.key, required this.child});

  @override
  State<ThemeSync> createState() => _ThemeSyncState();
}

class _ThemeSyncState extends State<ThemeSync> {
  bool? _last;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    AppColors.dark = isDark;
    if (_last != null && _last != isDark) AppTheme.rebuildAll();
    _last = isDark;
    return widget.child;
  }
}
