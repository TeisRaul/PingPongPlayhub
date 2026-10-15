import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/stripe_service.dart';
import '../theme/app_theme.dart';

class PaymentScreen extends StatefulWidget {
  final double amount;
  final String venueId;
  final String? destinationAccountId;

  const PaymentScreen({
    super.key, 
    required this.amount, 
    required this.venueId,
    this.destinationAccountId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isProcessing = false;

  // Controllers with mock card details for sandbox autofill
  final _cardNumberController = TextEditingController(text: '4111 1111 1111 1111');
  final _expiryController = TextEditingController(text: '12/29');
  final _cvvController = TextEditingController(text: '123');
  final _cardNameController = TextEditingController(text: 'Andrei Popescu');

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardNameController.dispose();
    super.dispose();
  }

  void _processPayment() async {
    setState(() => _isProcessing = true);
    
    // Add 5 RON platform fee to the total charge
    double totalAmount = widget.amount + 5.0;

    // Call our real StripeService
    bool success = await StripeService.instance.processPayment(
      context, 
      totalAmount, 
      widget.venueId,
      destinationAccountId: widget.destinationAccountId,
    );
    
    if (mounted) {
      setState(() => _isProcessing = false);
      if (success) {
        Navigator.pop(context, true);
      }
    }
  }



  // Google Pay / Apple Pay sunt oferite în fereastra de plată Stripe (PaymentSheet).
  // Butoanele rapide pornesc aceeași plată reală; nu mai există simulare de succes.
  void _processQuickWallet(String walletName) {
    _processPayment();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Plată Securizată', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.accent),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Banner for Sandbox autofill
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: AppColors.gold, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Secure Sandbox: Datele de card de test au fost pre-completate automat pentru o testare rapidă și securizată.',
                        style: TextStyle(color: AppColors.text70, fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rezervare Mese:', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                        Text('${widget.amount.toStringAsFixed(2)} RON', style: TextStyle(color: AppColors.text, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Taxă Platformă:', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                        Text('5.00 RON', style: TextStyle(color: AppColors.text, fontSize: 14)),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: AppColors.text24),
                    ),
                    Text('Total de Plată', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('${(widget.amount + 5.0).toStringAsFixed(2)} RON', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Wallet quick payments
              Text('Plătește rapid cu:', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _processQuickWallet('Google Pay'),
                      icon: FaIcon(FontAwesomeIcons.googlePay, color: AppColors.text, size: 24),
                      label: const Text('Google Pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.muted),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _processQuickWallet('Apple Pay'),
                      icon: const FaIcon(FontAwesomeIcons.apple, color: Colors.black, size: 18),
                      label: const Text('Apple Pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.text,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('SAU INTRODU CARDUL', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ],
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _cardNumberController,
                decoration: InputDecoration(
                  labelText: 'Număr Card',
                  prefixIcon: Icon(Icons.credit_card, color: AppColors.accent),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                keyboardType: TextInputType.number,
                validator: (val) => val != null && val.replaceAll(' ', '').length >= 16 ? null : 'Introduceți un număr valid (16 cifre)',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryController,
                      decoration: InputDecoration(
                        labelText: 'Expirare (LL/AA)',
                        prefixIcon: Icon(Icons.calendar_today, color: AppColors.accent),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: (val) => val != null && val.isNotEmpty ? null : 'Câmp obligatoriu',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      decoration: InputDecoration(
                        labelText: 'CVV',
                        prefixIcon: Icon(Icons.security, color: AppColors.accent),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      validator: (val) => val != null && val.length >= 3 ? null : 'Minim 3 cifre',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cardNameController,
                decoration: InputDecoration(
                  labelText: 'Numele de pe card',
                  prefixIcon: Icon(Icons.person, color: AppColors.accent),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val != null && val.isNotEmpty ? null : 'Câmp obligatoriu',
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Plătește Acum', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
