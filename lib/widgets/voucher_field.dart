import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/voucher_service.dart';
import '../theme/app_theme.dart';

/// Câmpul „Ai un cod de reducere?” de la rezervare.
/// Starea (codul aplicat) o ține ecranul părinte; aici doar se introduce și se verifică codul.
class VoucherField extends StatefulWidget {
  final String venueId;

  /// Prețul mesei pe care se aplică reducerea (fără extra / bar).
  final double Function() amount;
  final VoucherResult? applied;
  final ValueChanged<VoucherResult?> onChanged;

  const VoucherField({
    super.key,
    required this.venueId,
    required this.amount,
    required this.applied,
    required this.onChanged,
  });

  @override
  State<VoucherField> createState() => _VoucherFieldState();
}

class _VoucherFieldState extends State<VoucherField> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    final amount = widget.amount();
    if (code.isEmpty) {
      setState(() => _error = tr('vc.err_empty'));
      return;
    }
    if (amount <= 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await VoucherService.check(venueId: widget.venueId, code: code, amount: amount);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = res.ok ? null : res.errorMessage;
    });
    widget.onChanged(res.ok ? res : null);
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount();
    final applied = widget.applied;
    final active = applied != null && applied.validFor(amount);
    final stale = applied != null && applied.ok && !active;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? AppColors.good : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.confirmation_number_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(tr('vc.title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          if (active)
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('vc.applied', {'code': applied.code, 'amount': applied.discount.toStringAsFixed(applied.discount % 1 == 0 ? 0 : 2)}),
                    style: TextStyle(color: AppColors.good, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged(null);
                  },
                  child: Text(tr('vc.remove'), style: TextStyle(color: AppColors.muted)),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(hintText: tr('vc.hint'), isDense: true),
                    onSubmitted: (_) => _apply(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _apply,
                  child: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tr('vc.apply')),
                ),
              ],
            ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('vc.stale'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
