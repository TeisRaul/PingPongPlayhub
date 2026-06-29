import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/mock_locations.dart';
import '../../widgets/city_selector.dart';

class AddPublicLocationScreen extends StatefulWidget {
  const AddPublicLocationScreen({super.key});

  @override
  State<AddPublicLocationScreen> createState() => _AddPublicLocationScreenState();
}

class _AddPublicLocationScreenState extends State<AddPublicLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  
  String? _selectedCity;
  
  final Map<String, bool> _supportedSports = {
    'ping_pong': false,
    'padel': false,
    'tenis': false,
    'fotbal': false,
    'handbal': false,
    'baschet': false,
  };

  final Map<String, int> _resources = {};
  bool _isLoading = false;

  void _saveLocation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alege un oraș!'), backgroundColor: Colors.red),
      );
      return;
    }

    final activeSports = _supportedSports.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeSports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează măcar un sport!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('venues').doc();
      
      Map<String, List<Map<String, dynamic>>> layouts = {};
      
      for (String sport in activeSports) {
        int numTables = _resources[sport] ?? 1;
        layouts[sport] = List.generate(numTables, (index) => {
          'id': index + 1,
          'type': 'outdoor',
        });
      }

      await docRef.set({
        'uid': docRef.id,
        'venueName': _nameController.text.trim(),
        'city': _selectedCity,
        'address': _addressController.text.trim(),
        'isPublic': true,
        'pricePerHourText': '0 RON/oră (Gratis)',
        'supportedSports': activeSports,
        'layouts': layouts,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Locația a fost adăugată pe hartă!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Adaugă Locație Publică', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00FF66)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.park, size: 64, color: Color(0xFF00FF66)),
              const SizedBox(height: 16),
              const Text(
                'Această locație va apărea gratuită pentru toți jucătorii pe hartă.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nume Locație (ex: Parc IOR)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
                validator: (v) => v!.isEmpty ? 'Necesar' : null,
              ),
              const SizedBox(height: 16),
              
              CitySelectorField(
                labelText: 'Oraș',
                selectedCity: _selectedCity,
                cityOptions: romanianCities,
                onCitySelected: (c) => setState(() => _selectedCity = c),
                validator: (v) => v == null ? 'Necesar' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _addressController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Adresă (opțional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
              ),
              const SizedBox(height: 32),
              
              const Text('Sporturi disponibile:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              ..._supportedSports.keys.map((sport) {
                return Column(
                  children: [
                    CheckboxListTile(
                      title: Text(sport.toUpperCase(), style: const TextStyle(color: Colors.white)),
                      value: _supportedSports[sport],
                      activeColor: const Color(0xFF00FF66),
                      onChanged: (val) {
                        setState(() {
                          _supportedSports[sport] = val ?? false;
                          if (val == true) {
                            _resources[sport] = 1;
                          }
                        });
                      },
                    ),
                    if (_supportedSports[sport] == true)
                      Padding(
                        padding: const EdgeInsets.only(left: 32.0, right: 16.0, bottom: 16.0),
                        child: TextFormField(
                          initialValue: '1',
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Câte mese/terenuri de $sport?',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                          ),
                          onChanged: (v) => _resources[sport] = int.tryParse(v) ?? 1,
                        ),
                      ),
                  ],
                );
              }),
              
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF66),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black))
                    : const Text('SALVEAZĂ LOCAȚIA', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
