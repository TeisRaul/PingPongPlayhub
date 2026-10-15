import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../signup_screen.dart';
import '../../theme/app_theme.dart';

class AdminTrainerDetailScreen extends StatefulWidget {
  final String trainerId;
  final Map<String, dynamic> trainerData;

  const AdminTrainerDetailScreen({super.key, required this.trainerId, required this.trainerData});

  @override
  State<AdminTrainerDetailScreen> createState() => _AdminTrainerDetailScreenState();
}

class _AdminTrainerDetailScreenState extends State<AdminTrainerDetailScreen> {
  late TextEditingController _pricePerMonthController;
  late TextEditingController _pricePerSessionController;
  late TextEditingController _ibanController;
  late bool _isTrainer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pricePerMonthController = TextEditingController(text: (widget.trainerData['trainerPricePerMonth'] ?? '').toString());
    _pricePerSessionController = TextEditingController(text: (widget.trainerData['trainerPricePerSession'] ?? widget.trainerData['trainerPrice'] ?? '').toString());
    _ibanController = TextEditingController(text: widget.trainerData['trainerIban'] ?? '');
    _isTrainer = widget.trainerData['isTrainer'] ?? false;
  }

  @override
  void dispose() {
    _pricePerMonthController.dispose();
    _pricePerSessionController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.trainerId).update({
        'trainerPricePerMonth': double.tryParse(_pricePerMonthController.text),
        'trainerPricePerSession': double.tryParse(_pricePerSessionController.text),
        'trainerIban': _ibanController.text.trim(),
        'isTrainer': _isTrainer,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Date antrenor salvate!'), backgroundColor: Colors.green));
        Navigator.pop(context); // Go back after saving
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Detalii Antrenor', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editează profilul de antrenor',
              style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // Is Trainer Toggle
            SwitchListTile(
              title: Text('Status Antrenor Activ', style: TextStyle(color: AppColors.text)),
              subtitle: Text('Dacă dezactivezi, acest utilizator nu va mai apărea ca antrenor', style: TextStyle(color: AppColors.muted)),
              value: _isTrainer,
              activeColor: AppColors.gold,
              onChanged: (val) {
                setState(() {
                  _isTrainer = val;
                });
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pricePerMonthController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Preț / lună (RON)',
                      labelStyle: TextStyle(color: AppColors.muted),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _pricePerSessionController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Preț / ședință',
                      labelStyle: TextStyle(color: AppColors.muted),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Trainer IBAN
            TextField(
              controller: _ibanController,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                labelText: 'Cont IBAN (opțional)',
                labelStyle: TextStyle(color: AppColors.muted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
              ),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignupScreen(
                      isEditMode: true,
                      userId: widget.trainerId,
                      userData: widget.trainerData,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_document),
              label: const Text('Editează Profil Antrenor Complet (Formular)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: Colors.amberAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.amberAccent),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _isSaving ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black))
                  : const Text('SALVEAZĂ MODIFICĂRILE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
