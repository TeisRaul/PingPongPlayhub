import 'package:flutter/material.dart';

class PaymentScreen extends StatefulWidget {
  final double amount;
  const PaymentScreen({super.key, required this.amount});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isProcessing = false;

  void _processPayment() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isProcessing = true);
      // Simulăm procesarea plății
      await Future.delayed(const Duration(seconds: 2));
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plata a fost procesată cu succes!'), backgroundColor: Colors.green));
        Navigator.pop(context, true); // Întoarce succes
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plată Securizată'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    const Text('Total de Plată', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('${widget.amount.toStringAsFixed(2)} RON', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text('Detalii Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Număr Card',
                  prefixIcon: const Icon(Icons.credit_card, color: Color(0xFF00E5FF)),
                  filled: true,
                  fillColor: const Color(0xFF131A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                keyboardType: TextInputType.number,
                validator: (val) => val != null && val.length >= 16 ? null : 'Introduceți un număr valid (16 cifre)',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
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
                decoration: InputDecoration(
                  labelText: 'Numele de pe card',
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF00E5FF)),
                  filled: true,
                  fillColor: const Color(0xFF131A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val != null && val.isNotEmpty ? null : 'Câmp obligatoriu',
              ),
              const Spacer(),
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
