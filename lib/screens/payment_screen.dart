import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../services/stripe_service.dart';
import '../theme/app_theme.dart';

class PaymentScreen extends StatefulWidget {
  final double amount;
  final String venueId;
  final String? destinationAccountId;
  /// Ce se plătește (vezi StripeService.processPayment).
  final Map<String, dynamic>? purpose;
  /// Taxa platformei adăugată peste [amount] (0 la partea unui jucător: e deja inclusă).
  final double fee;

  const PaymentScreen({
    super.key,
    required this.amount,
    required this.venueId,
    this.destinationAccountId,
    this.purpose,
    this.fee = 5.0,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isProcessing = false;

  double get _total => widget.amount + widget.fee;

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    // Datele cardului se introduc doar în fereastra Stripe (PaymentSheet pe telefon,
    // Stripe Checkout pe web); aplicația nu le vede niciodată.
    final bool success = await StripeService.instance.processPayment(
      context,
      _total,
      widget.venueId,
      destinationAccountId: widget.destinationAccountId,
      purpose: widget.purpose,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (success) Navigator.pop(context, true);
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 14)),
        Text(value, style: TextStyle(color: AppColors.text, fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(tr('pay.title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.accent),
          onPressed: _isProcessing ? null : () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  if (widget.fee > 0) ...[
                    _row(tr('pay.booking'), '${widget.amount.toStringAsFixed(2)} RON'),
                    const SizedBox(height: 8),
                    _row(tr('pay.fee'), '${widget.fee.toStringAsFixed(2)} RON'),
                  ] else
                    _row(tr('split.your_share'), '${widget.amount.toStringAsFixed(2)} RON'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: AppColors.text24),
                  ),
                  Text(tr('pay.total'), style: TextStyle(color: AppColors.muted, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('${_total.toStringAsFixed(2)} RON',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.good, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    kIsWeb ? tr('pay.secure_web') : tr('pay.secure_app'),
                    style: TextStyle(color: AppColors.text70, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Icon(Icons.credit_card),
              label: Text(
                tr('pay.btn', {'amount': _total.toStringAsFixed(2)}),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
