import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/account_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// "Date și cont": export de date și ștergerea contului (cerință GDPR / magazine de aplicații).
class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  bool _exporting = false;
  bool _deleting = false;
  bool _pushOn = false;
  bool _emailOn = true;
  bool _prefsLoading = true;
  DocumentReference<Map<String, dynamic>>? _prefRef;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  /// Setările de notificări stau pe profilul jucătorului sau, la conturile de sală, pe documentul sălii.
  Future<void> _loadPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final db = FirebaseFirestore.instance;
      var ref = db.collection('users').doc(user.uid);
      var snap = await ref.get();
      if (!snap.exists) {
        ref = db.collection('venues').doc(user.uid);
        snap = await ref.get();
      }
      _prefRef = ref;
      final data = snap.data() ?? <String, dynamic>{};
      final push = await PushService.instance.isEnabled();
      if (!mounted) return;
      setState(() {
        _emailOn = data['emailNotifications'] != false;
        _pushOn = push && data['pushNotifications'] != false;
        _prefsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _prefsLoading = false);
    }
  }

  Future<void> _savePref(String field, bool value) async {
    try {
      await _prefRef?.set({field: value}, SetOptions(merge: true));
    } catch (_) {
      // setarea locală rămâne; se va reîncerca la următoarea schimbare
    }
  }

  Future<void> _togglePush(bool value) async {
    if (value) {
      final ok = await PushService.instance.enable();
      if (!ok) {
        _snack(tr('acct.push_blocked'));
        return;
      }
    } else {
      await PushService.instance.disable();
    }
    if (!mounted) return;
    setState(() => _pushOn = value);
    await _savePref('pushNotifications', value);
  }

  Future<void> _toggleEmail(bool value) async {
    setState(() => _emailOn = value);
    await _savePref('emailNotifications', value);
  }

  Widget _notificationsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.notifications_active, color: AppColors.accent),
                const SizedBox(width: 10),
                Text(tr('acct.notif_title'), style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (PushService.instance.supported)
            SwitchListTile(
              value: _pushOn,
              onChanged: _prefsLoading ? null : _togglePush,
              title: Text(tr('acct.push_title'), style: TextStyle(color: AppColors.text)),
              subtitle: Text(tr('acct.push_desc'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          SwitchListTile(
            value: _emailOn,
            onChanged: _prefsLoading ? null : _toggleEmail,
            title: Text(tr('acct.email_title'), style: TextStyle(color: AppColors.text)),
            subtitle: Text(tr('acct.email_desc'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await AccountService.exportData();
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(tr('acct.export_done_title'), style: TextStyle(color: AppColors.text)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('acct.export_copied'), style: TextStyle(color: AppColors.accent, fontSize: 13)),
                const SizedBox(height: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        json.length > 6000 ? '${json.substring(0, 6000)}\n…' : json,
                        style: TextStyle(color: AppColors.text70, fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: json)),
              child: Text(tr('acct.export_copy')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.close'))),
          ],
        ),
      );
    } catch (_) {
      _snack(tr('acct.export_failed'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final word = tr('acct.confirm_word');
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(tr('acct.delete_confirm_title'), style: TextStyle(color: AppColors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('acct.delete_confirm_body', {'word': word}), style: TextStyle(color: AppColors.text70)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: AppColors.text),
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(hintText: word),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('acct.cancel'))),
            TextButton(
              onPressed: controller.text.trim().toUpperCase() == word.toUpperCase()
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(tr('acct.delete_title'), style: TextStyle(color: AppColors.bad)),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final ok = await AccountService.deleteAccount();
      if (!mounted) return;
      if (!ok) {
        _snack(tr('acct.admin_blocked'));
        setState(() => _deleting = false);
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      _snack(tr('acct.delete_failed'));
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    String? note,
    required String button,
    required bool busy,
    required VoidCallback onPressed,
    required bool danger,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger ? AppColors.bad.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: TextStyle(color: AppColors.text70, fontSize: 14, height: 1.4)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note, style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: danger
                  ? ElevatedButton.styleFrom(backgroundColor: AppColors.bad, foregroundColor: Colors.white)
                  : null,
              onPressed: (_exporting || _deleting) ? null : onPressed,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(button),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('acct.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _notificationsCard(),
          _section(
            icon: Icons.download,
            color: AppColors.accent,
            title: tr('acct.export_title'),
            description: tr('acct.export_desc'),
            button: tr('acct.export_btn'),
            busy: _exporting,
            onPressed: _export,
            danger: false,
          ),
          _section(
            icon: Icons.delete_forever,
            color: AppColors.bad,
            title: tr('acct.delete_title'),
            description: tr('acct.delete_desc'),
            note: tr('acct.venue_note'),
            button: tr('acct.delete_btn'),
            busy: _deleting,
            onPressed: _delete,
            danger: true,
          ),
        ],
      ),
    );
  }
}
