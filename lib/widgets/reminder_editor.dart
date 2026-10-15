import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';
import '../utils/reminder_config.dart';

/// Formularul în care jucătorul alege când și de câte ori primește reminderul.
/// Dacă [matchStart] e dat, arată și momentele exacte la care va fi notificat.
class ReminderEditor extends StatelessWidget {
  final ReminderConfig value;
  final ValueChanged<ReminderConfig> onChanged;
  final DateTime? matchStart;

  const ReminderEditor({super.key, required this.value, required this.onChanged, this.matchStart});

  @override
  Widget build(BuildContext context) {
    final cfg = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: cfg.enabled,
          onChanged: (v) => onChanged(cfg.copyWith(enabled: v)),
          title: Text(tr('rem.enabled'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        ),
        if (cfg.enabled) ...[
          const SizedBox(height: 4),
          _dropdown(
            label: tr('rem.first'),
            value: cfg.firstMin,
            options: ReminderConfig.firstOptions,
            labelOf: ReminderConfig.firstLabel,
            onChanged: (v) => onChanged(cfg.copyWith(firstMin: v)),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: tr('rem.repeat'),
            value: cfg.repeatEveryMin,
            options: ReminderConfig.repeatOptions,
            labelOf: ReminderConfig.repeatLabel,
            onChanged: (v) => onChanged(cfg.copyWith(repeatEveryMin: v)),
          ),
          if (cfg.repeats) ...[
            const SizedBox(height: 12),
            Text(tr('rem.repeat_how'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(tr('rem.mode_count')),
                  selected: !cfg.untilStart,
                  onSelected: (_) => onChanged(cfg.copyWith(repeatMode: 'count')),
                ),
                ChoiceChip(
                  label: Text(tr('rem.mode_until')),
                  selected: cfg.untilStart,
                  onSelected: (_) => onChanged(cfg.copyWith(repeatMode: 'until_start')),
                ),
              ],
            ),
            if (!cfg.untilStart)
              Row(
                children: [
                  Expanded(
                    child: Text(tr('rem.count', {'n': '${cfg.repeatCount}'}), style: TextStyle(color: AppColors.text)),
                  ),
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: AppColors.accent),
                    onPressed: cfg.repeatCount > 1 ? () => onChanged(cfg.copyWith(repeatCount: cfg.repeatCount - 1)) : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, color: AppColors.accent),
                    onPressed: cfg.repeatCount < ReminderConfig.maxRepeatCount
                        ? () => onChanged(cfg.copyWith(repeatCount: cfg.repeatCount + 1))
                        : null,
                  ),
                ],
              ),
          ],
          if (matchStart != null) ...[
            const SizedBox(height: 14),
            _preview(cfg, matchStart!),
          ],
        ],
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required int value,
    required List<int> options,
    required String Function(int) labelOf,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: options.contains(value) ? value : options.first,
      isExpanded: true,
      dropdownColor: AppColors.card2,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.muted),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
      ),
      style: TextStyle(color: AppColors.text),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(labelOf(o)))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _preview(ReminderConfig cfg, DateTime start) {
    final now = DateTime.now();
    final upcoming = cfg.fireTimes(start).where((t) => t.isAfter(now)).toList();
    final fmt = DateFormat('dd.MM HH:mm');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: upcoming.isEmpty
          ? Text(tr('rem.preview_none'), style: TextStyle(color: Colors.orangeAccent, fontSize: 13))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('rem.preview'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                for (final t in upcoming.take(8))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active_outlined, size: 14, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(fmt.format(t), style: TextStyle(color: AppColors.text)),
                      ],
                    ),
                  ),
                if (upcoming.length > 8)
                  Text('+${upcoming.length - 8}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
    );
  }
}

/// Dialogul de reminder pentru un meci anume (buton "Reminder" pe cardul meciului).
Future<void> showMatchReminderDialog(BuildContext context, String matchId, Map<String, dynamic> match) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  DateTime? start;
  try {
    start = dateAtHour(match['date'].toString(), hourValue(match['startHour']));
  } catch (_) {}

  ReminderConfig general = ReminderConfig.defaults;
  ReminderConfig? custom;
  try {
    general = await ReminderService.loadDefault(uid);
    custom = await ReminderService.loadForMatch(matchId, uid);
  } catch (_) {
    // folosim valorile implicite; salvarea va arăta eroarea dacă e cazul
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => _MatchReminderDialog(
      matchId: matchId,
      uid: uid,
      start: start,
      general: general,
      custom: custom,
    ),
  );
}

class _MatchReminderDialog extends StatefulWidget {
  final String matchId;
  final String uid;
  final DateTime? start;
  final ReminderConfig general;
  final ReminderConfig? custom;

  const _MatchReminderDialog({
    required this.matchId,
    required this.uid,
    required this.start,
    required this.general,
    required this.custom,
  });

  @override
  State<_MatchReminderDialog> createState() => _MatchReminderDialogState();
}

class _MatchReminderDialogState extends State<_MatchReminderDialog> {
  late ReminderConfig _cfg = widget.custom ?? widget.general;
  late bool _hasCustom = widget.custom != null;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ReminderService.saveForMatch(widget.matchId, widget.uid, _cfg);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.saved')), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.error', {'e': '$e'})), backgroundColor: Colors.red));
    }
  }

  Future<void> _useDefault() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ReminderService.clearForMatch(widget.matchId, widget.uid);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.reset_done'))));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('rem.error', {'e': '$e'})), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(tr('rem.for_match'), style: TextStyle(color: AppColors.text, fontSize: 18)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hasCustom ? tr('rem.has_custom') : tr('rem.using_default'),
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ReminderEditor(value: _cfg, matchStart: widget.start, onChanged: (c) => setState(() => _cfg = c)),
            ],
          ),
        ),
      ),
      actions: [
        if (_hasCustom)
          TextButton(
            onPressed: _busy ? null : _useDefault,
            child: Text(tr('rem.use_default'), style: TextStyle(color: AppColors.muted)),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
          onPressed: _busy ? null : _save,
          child: Text(tr('rem.save')),
        ),
      ],
    );
  }
}
