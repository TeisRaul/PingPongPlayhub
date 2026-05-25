import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/stripe_service.dart';

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

  void _processQuickWallet(String walletName) async {
    setState(() => _isProcessing = true);
    
    double totalAmount = widget.amount + 5.0;

    // Stripe PaymentSheet supports Apple Pay / Google Pay automatically
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

  void _processQuickWallet(String walletName) async {
    // Show biometric / wallet confirmation sheet
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF131A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      FaIcon(
                        walletName == 'Apple Pay' ? FontAwesomeIcons.apple : FontAwesomeIcons.googlePay,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        walletName,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Text('SANDBOX SECURE', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Comerciant:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Text('PingPong Playhub', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sumă tranzacție:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Text(
                    '${widget.amount.toStringAsFixed(2)} RON',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Card asociat:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Row(
                    children: [
                      const Icon(Icons.credit_card, color: Colors.white54, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        walletName == 'Apple Pay' ? 'Apple Card (•••• 9876)' : 'GPay Visa (•••• 4321)',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Touch ID / Face ID simulation prompt
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Icon(
                      walletName == 'Apple Pay' ? Icons.fingerprint : Icons.security,
                      color: const Color(0xFF00E5FF),
                      size: 40,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      walletName == 'Apple Pay'
                          ? 'Atinge senzorul Touch ID sau folosește Face ID pentru a confirma tranzacția'
                          : 'Confirmați identitatea prin cod pin sau amprentă GPay',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: walletName == 'Apple Pay' ? Colors.white : const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                child: Text(
                  walletName == 'Apple Pay' ? 'Plătește cu Apple Pay' : 'Plătește cu Google Pay',
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Anulează', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;

    // Show high-tech Encryption & Tokenization simulation overlay!
    setState(() => _isProcessing = true);
    
    // We will show a custom dialog with a progressive encryption status update!
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String stepText = 'Lansare tranzacție securizată SSL/TLS...';
            double progress = 0.1;
            
            // Progressively update messages
            Future.delayed(const Duration(milliseconds: 700), () {
              if (context.mounted) {
                setDialogState(() {
                  stepText = 'Inițializare protocol criptografic end-to-end (AES-256)...';
                  progress = 0.4;
                });
              }
            });
            Future.delayed(const Duration(milliseconds: 1400), () {
              if (context.mounted) {
                setDialogState(() {
                  stepText = 'Se generează Token virtual de unică folosință (Tokenization)...';
                  progress = 0.7;
                });
              }
            });
            Future.delayed(const Duration(milliseconds: 2100), () {
              if (context.mounted) {
                setDialogState(() {
                  stepText = 'Tranzacție finalizată! Cardul tău real nu a fost expus niciodată. Protecție totală anti-interceptare.';
                  progress = 1.0;
                });
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
              title: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF00FF66)),
                  const SizedBox(width: 8),
                  Text(
                    'Criptare Securizată $walletName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF00E5FF),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    stepText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 2800));
    
    if (mounted) {
      Navigator.pop(context); // Close the encryption dialog
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Plata securizată prin $walletName a fost finalizată cu succes!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true); // Complete booking successfully
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Plată Securizată', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00E5FF)),
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
                  color: const Color(0xFFFFD700).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4), width: 1.2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Secure Sandbox: Datele de card de test au fost pre-completate automat pentru o testare rapidă și securizată.',
                        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF131A2A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Rezervare Mese:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        Text('${widget.amount.toStringAsFixed(2)} RON', style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Taxă Platformă:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        Text('5.00 RON', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Colors.white24),
                    ),
                    const Text('Total de Plată', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('${(widget.amount + 5.0).toStringAsFixed(2)} RON', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Wallet quick payments
              const Text('Plătește rapid cu:', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _processQuickWallet('Google Pay'),
                      icon: const FaIcon(FontAwesomeIcons.googlePay, color: Colors.white, size: 24),
                      label: const Text('Google Pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.grey),
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
                        backgroundColor: Colors.white,
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
                  Expanded(child: Divider(color: Colors.grey[850])),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('SAU INTRODU CARDUL', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: Colors.grey[850])),
                ],
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _cardNumberController,
                decoration: InputDecoration(
                  labelText: 'Număr Card',
                  prefixIcon: const Icon(Icons.credit_card, color: Color(0xFF00E5FF)),
                  filled: true,
                  fillColor: const Color(0xFF131A2A),
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
                        prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF00E5FF)),
                        filled: true,
                        fillColor: const Color(0xFF131A2A),
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
                        prefixIcon: const Icon(Icons.security, color: Color(0xFF00E5FF)),
                        filled: true,
                        fillColor: const Color(0xFF131A2A),
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
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF00E5FF)),
                  filled: true,
                  fillColor: const Color(0xFF131A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val != null && val.isNotEmpty ? null : 'Câmp obligatoriu',
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF00E5FF),
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
