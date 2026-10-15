import 'package:flutter/material.dart';
import '../l10n/app_locales.dart';
import '../l10n/strings.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';

/// Alegerea limbii aplicației.
/// [firstTime] = true: afișat o singură dată după primul login (fără buton de înapoi).
class LanguageScreen extends StatefulWidget {
  final bool firstTime;

  const LanguageScreen({super.key, this.firstTime = false});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = AppLocales.current.value;
  }

  void _pick(String code) {
    // Aplicăm imediat, ca utilizatorul să vadă textele schimbându-se.
    AppLocales.apply(code);
    setState(() => _selected = code);
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await AppLocales.saveForCurrentUser(_selected);
    } catch (e) {
      debugPrint('Nu am putut salva limba: $e');
    }
    if (!mounted) return;
    // Reîncărcăm aplicația de la Dashboard, ca toate ecranele să folosească limba nouă.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.firstTime,
      child: Scaffold(
        appBar: widget.firstTime
            ? null
            : AppBar(
                title: Text(tr('lang.title')),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.firstTime) const SizedBox(height: 24),
                Text(
                  tr('lang.choose'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Text(tr('lang.choose_sub'), style: TextStyle(color: AppColors.muted, fontSize: 14)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      for (final lang in AppLocales.languages) _buildTile(lang),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _saving ? null : _confirm,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(tr('common.continue').toUpperCase()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(AppLanguage lang) {
    final bool isSelected = _selected == lang.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(lang.code),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.text12,
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.card2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lang.tag,
                    style: TextStyle(
                      color: isSelected ? AppColors.accent : AppColors.text70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    lang.name,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected) Icon(Icons.check_circle, color: AppColors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
