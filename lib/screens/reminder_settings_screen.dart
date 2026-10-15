import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../utils/reminder_config.dart';
import '../widgets/reminder_editor.dart';

/// Setările generale de reminder (se aplică tuturor meciurilor, în afară de cele cu setări proprii).
class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  ReminderConfig _cfg = ReminderConfig.defaults;
  bool _loading = true;
  bool _saving = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final cfg = await ReminderService.loadDefault(uid);
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReminderService.saveDefault(uid, _cfg);
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.saved')), backgroundColor: Colors.green));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.error', {'e': '$e'})), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(tr('rem.title'), style: TextStyle(color: AppColors.text, fontSize: 18)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(tr('rem.desc'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ReminderEditor(value: _cfg, onChanged: (c) => setState(() => _cfg = c)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                        : Text(tr('rem.save'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }
}
