import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VenueSignupScreen extends StatefulWidget {
  const VenueSignupScreen({super.key});

  @override
  State<VenueSignupScreen> createState() => _VenueSignupScreenState();
}

class _VenueSignupScreenState extends State<VenueSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers
  final _venueNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _websiteController = TextEditingController();

  final _indoorTablesController = TextEditingController(text: '0');
  final _outdoorTablesController = TextEditingController(text: '0');

  // Operating hours controllers
  final _lvOpenController = TextEditingController(text: '08:00');
  final _lvCloseController = TextEditingController(text: '22:00');
  final _sOpenController = TextEditingController(text: '09:00');
  final _sCloseController = TextEditingController(text: '21:00');
  final _dOpenController = TextEditingController(text: '09:00');
  final _dCloseController = TextEditingController(text: '18:00');

  final _priceController = TextEditingController(text: '30 RON/oră înainte de 17:00, 40 RON/oră după 17:00');

  final _cuiController = TextEditingController();
  final _ibanController = TextEditingController();

  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Facilities checklist mapping
  final Map<String, bool> _facilities = {
    'Vestiare / Dușuri': false,
    'Aer condiționat / Încălzire': false,
    'Închiriere palete / mingi': false,
    'Antrenor personal / Cursuri': false,
    'Parcare proprie': false,
    'Bar / Automat de băuturi': false,
  };

  @override
  void dispose() {
    _venueNameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _websiteController.dispose();
    _indoorTablesController.dispose();
    _outdoorTablesController.dispose();
    _lvOpenController.dispose();
    _lvCloseController.dispose();
    _sOpenController.dispose();
    _sCloseController.dispose();
    _dOpenController.dispose();
    _dCloseController.dispose();
    _priceController.dispose();
    _cuiController.dispose();
    _ibanController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final initialTimeStr = controller.text;
    int initialHour = 8;
    int initialMinute = 0;
    
    if (initialTimeStr.contains(':')) {
      final parts = initialTimeStr.split(':');
      initialHour = int.tryParse(parts[0]) ?? 8;
      initialMinute = int.tryParse(parts[1]) ?? 0;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF),
              onPrimary: Colors.black,
              surface: Color(0xFF131A2A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minuteStr = picked.minute.toString().padLeft(2, '0');
      setState(() {
        controller.text = '$hourStr:$minuteStr';
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parolele nu coincid!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // 1. Create auth account in Firebase
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      // 2. Map selected facilities to standard list tags
      final List<String> selectedFacilities = [];
      _facilities.forEach((facility, isSelected) {
        if (isSelected) {
          if (facility == 'Vestiare / Dușuri') selectedFacilities.add('vestiare');
          if (facility == 'Aer condiționat / Încălzire') selectedFacilities.add('aer_conditionat');
          if (facility == 'Închiriere palete / mingi') selectedFacilities.add('inchiriere_palete');
          if (facility == 'Antrenor personal / Cursuri') selectedFacilities.add('antrenor');
          if (facility == 'Parcare proprie') selectedFacilities.add('parcare');
          if (facility == 'Bar / Automat de băuturi') selectedFacilities.add('bar');
        }
      });

      // 3. Estimate hourly price from text description
      final priceText = _priceController.text;
      final numberRegExp = RegExp(r'\d+');
      final match = numberRegExp.firstMatch(priceText);
      double parsedPrice = 35.0; // default standard
      if (match != null) {
        parsedPrice = double.tryParse(match.group(0) ?? '') ?? 35.0;
      }

      final int indoorTables = int.tryParse(_indoorTablesController.text) ?? 0;
      final int outdoorTables = int.tryParse(_outdoorTablesController.text) ?? 0;
      final int totalTables = indoorTables + outdoorTables;

      // 4. Save to venues Firestore collection
      await FirebaseFirestore.instance.collection('venues').doc(uid).set({
        'venueId': uid,
        'venueName': _venueNameController.text.trim(),
        'contactPerson': _contactPersonController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'email': email,
        'city': _cityController.text.trim(),
        'address': _addressController.text.trim(),
        'website': _websiteController.text.trim(),
        'indoorTables': indoorTables,
        'outdoorTables': outdoorTables,
        'totalTables': totalTables,
        'facilities': selectedFacilities,
        'pricePerHour': parsedPrice,
        'pricePerHourText': priceText,
        'schedule': {
          'Luni-Vineri': '${_lvOpenController.text} - ${_lvCloseController.text}',
          'Sambata': '${_sOpenController.text} - ${_sCloseController.text}',
          'Duminica': '${_dOpenController.text} - ${_dCloseController.text}',
        },
        'cui': _cuiController.text.trim(),
        'iban': _ibanController.text.trim(),
        'blockedDates': [],
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Show success modal
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF00E5FF), size: 28),
                  SizedBox(width: 10),
                  Text('Cont Creat!', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: const Text(
                'Contul de Sală a fost creat cu succes!\n\nAcesta va deveni complet funcțional și vizibil pentru jucători după ce va fi aprobat manual de către administratorul PingPong Playhub.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Return to login
                  },
                  child: const Text('OK', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la crearea contului: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1.5),
        ],
      ),
    );
  }

  Widget _buildTimeSelectorRow(String label, TextEditingController openCtrl, TextEditingController closeCtrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ),
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: () => _selectTime(context, openCtrl),
              child: IgnorePointer(
                child: TextFormField(
                  controller: openCtrl,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Deschidere',
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: () => _selectTime(context, closeCtrl),
              child: IgnorePointer(
                child: TextFormField(
                  controller: closeCtrl,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Închidere',
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Înregistrare Sală / Club'),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.storefront,
                  size: 64,
                  color: Color(0xFF00E5FF),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Creează Cont de Sală',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Completează detaliile clubului tău pentru a începe organizarea de turnee și meciuri.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),

                // 1. Date Contact Business
                _buildSectionHeader('1. Informații Sală & Contact'),
                TextFormField(
                  controller: _venueNameController,
                  decoration: const InputDecoration(
                    labelText: 'Numele Sălii / Clubului',
                    prefixIcon: Icon(Icons.business),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci numele sălii';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactPersonController,
                  decoration: const InputDecoration(
                    labelText: 'Nume Administrator / Persoană de contact',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci persoana de contact';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefon Business',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Te rugăm să introduci numărul de telefon';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Business (pentru logare)',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty || !value.contains('@')) {
                      return 'Te rugăm să introduci un email valid';
                    }
                    return null;
                  },
                ),

                // 2. Adresă și Mediu Online
                _buildSectionHeader('2. Adresă & Locație'),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(
                          labelText: 'Oraș',
                          prefixIcon: Icon(Icons.location_city),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Oraș obligatoriu';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Adresă completă',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Adresă obligatorie';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _websiteController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Website / Rețele Sociale (Opțional)',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),

                // 3. Dotări și Facilități
                _buildSectionHeader('3. Detalii Sală & Dotări'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _indoorTablesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Mese Indoor',
                          prefixIcon: Icon(Icons.table_bar),
                        ),
                        validator: (value) {
                          if (value == null || int.tryParse(value) == null) {
                            return 'Număr invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _outdoorTablesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Mese Outdoor (dacă există)',
                          prefixIcon: Icon(Icons.wb_sunny_outlined),
                        ),
                        validator: (value) {
                          if (value == null || int.tryParse(value) == null) {
                            return 'Număr invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Facilități incluse:',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  color: const Color(0xFF131A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Column(
                      children: _facilities.keys.map((String key) {
                        return CheckboxListTile(
                          title: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          activeColor: const Color(0xFF00E5FF),
                          checkColor: Colors.black,
                          value: _facilities[key],
                          onChanged: (bool? value) {
                            setState(() {
                              _facilities[key] = value ?? false;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // 4. Program și Tarife
                _buildSectionHeader('4. Program de Funcționare & Tarife'),
                _buildTimeSelectorRow('Luni - Vineri', _lvOpenController, _lvCloseController),
                _buildTimeSelectorRow('Sâmbătă', _sOpenController, _sCloseController),
                _buildTimeSelectorRow('Duminică', _dOpenController, _dCloseController),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Tarif pe oră (MVP - Text explicativ)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să descrii tariful pe oră';
                    }
                    return null;
                  },
                ),

                // 5. Date Financiare
                _buildSectionHeader('5. Date Financiare (Salarizare)'),
                TextFormField(
                  controller: _cuiController,
                  decoration: const InputDecoration(
                    labelText: 'CUI / Date Fiscale (Opțional pentru MVP)',
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ibanController,
                  decoration: const InputDecoration(
                    labelText: 'IBAN de încasare plăți',
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci contul IBAN al clubului';
                    }
                    return null;
                  },
                ),

                // 6. Securitate
                _buildSectionHeader('6. Securitate Cont'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Parolă',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Parola trebuie să aibă minim 6 caractere';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirmă parolă',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Te rugăm să confirmi parola';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const Text('ÎNREGISTREAZĂ SALA'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
