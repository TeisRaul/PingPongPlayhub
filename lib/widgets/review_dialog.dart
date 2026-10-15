import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Fereastra de recenzie (stele + comentariu). [onSubmit] salvează; dacă aruncă, fereastra rămâne deschisă.
Future<bool> showReviewDialog(
  BuildContext context, {
  required String title,
  required Future<void> Function(int rating, String comment) onSubmit,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ReviewDialog(title: title, onSubmit: onSubmit),
  );
  return result == true;
}

class _ReviewDialog extends StatefulWidget {
  final String title;
  final Future<void> Function(int rating, String comment) onSubmit;

  const _ReviewDialog({required this.title, required this.onSubmit});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSubmit(_rating, _comment.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(widget.title, style: TextStyle(color: AppColors.text, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _saving ? null : () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: AppColors.gold,
                      size: 34,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _comment,
              enabled: !_saving,
              maxLines: 3,
              maxLength: 300,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(hintText: tr('rev.comment_hint')),
            ),
            if (_failed) Text(tr('rev.failed'), style: TextStyle(color: AppColors.bad, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('acct.cancel'))),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('rev.send')),
        ),
      ],
    );
  }
}
