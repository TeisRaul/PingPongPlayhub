import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

String themeModeLabel(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return tr('theme.light');
    case ThemeMode.system:
      return tr('theme.system');
    case ThemeMode.dark:
      return tr('theme.dark');
  }
}

IconData themeModeIcon(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return Icons.light_mode;
    case ThemeMode.system:
      return Icons.brightness_auto;
    case ThemeMode.dark:
      return Icons.dark_mode;
  }
}

/// Fereastra de alegere a temei (luminoasă / întunecată / sistem).
Future<void> showThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, current, _) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('theme.title'), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final m in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
                ListTile(
                  leading: Icon(themeModeIcon(m), color: m == current ? AppColors.accent : AppColors.text70),
                  title: Text(
                    themeModeLabel(m),
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: m == current ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: m == current ? Icon(Icons.check, color: AppColors.accent) : null,
                  onTap: () {
                    ThemeController.set(m);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Buton mic pentru schimbarea temei, folosit pe ecranele de dinainte de autentificare.
class ThemePickerButton extends StatelessWidget {
  const ThemePickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => IconButton(
        tooltip: tr('theme.title'),
        icon: Icon(themeModeIcon(mode), color: AppColors.text70, size: 22),
        onPressed: () => showThemeSheet(context),
      ),
    );
  }
}
