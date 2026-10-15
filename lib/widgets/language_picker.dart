import 'package:flutter/material.dart';

import '../l10n/app_locales.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Buton mic pentru alegerea limbii, folosit pe ecranele de dinainte de autentificare.
/// Alegerea se aplică imediat, se ține minte pe dispozitiv și se salvează pe cont după login.
class LanguagePickerButton extends StatelessWidget {
  const LanguagePickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocales.current,
      builder: (context, code, _) {
        return PopupMenuButton<String>(
          tooltip: tr('auth.language'),
          color: AppColors.card,
          onSelected: AppLocales.chooseBeforeLogin,
          itemBuilder: (_) => [
            for (final l in AppLocales.languages)
              PopupMenuItem<String>(
                value: l.code,
                child: Row(
                  children: [
                    Expanded(child: Text(l.name, style: TextStyle(color: AppColors.text))),
                    if (l.code == code) Icon(Icons.check, color: AppColors.accent, size: 18),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, color: AppColors.text70, size: 20),
                const SizedBox(width: 4),
                Text(
                  AppLocales.byCode(code).tag,
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
