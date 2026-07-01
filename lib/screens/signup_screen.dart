import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'avatar_screen.dart';
import '../widgets/city_selector.dart';
import '../data/mock_locations.dart';

class SignupScreen extends StatefulWidget {
  final String? initialFirstName;
  final String? initialLastName;
  final String? initialEmail;
  final bool isEditMode;
  final String? userId;
  final Map<String, dynamic>? userData;

  const SignupScreen({
    super.key, 
    this.initialFirstName, 
    this.initialLastName, 
    this.initialEmail,
    this.isEditMode = false,
    this.userId,
    this.userData,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final _firstNameController = TextEditingController(text: widget.initialFirstName ?? '');
  late final _lastNameController = TextEditingController(text: widget.initialLastName ?? '');
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');
  final _usernameController = TextEditingController();
  
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  String? _selectedCity;

  String _fullPhoneNumber = '';
  double _passwordStrength = 0.0;
  String _passwordStrengthText = '';
  Color _passwordStrengthColor = Colors.transparent;

  // Trainer variables
  bool _isTrainer = false;
  String? _selectedVenueId;
  String _pricingType = 'Ambele';
  final _trainerPricePerMonthController = TextEditingController();
  final _trainerPricePerSessionController = TextEditingController();
  final _trainerIbanController = TextEditingController();
  List<Map<String, dynamic>> _venuesList = [];

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordStrength);
    _fetchVenues();
    
    if (widget.isEditMode && widget.userData != null) {
      _usernameController.text = widget.userData!['username'] ?? '';
      _phoneController.text = (widget.userData!['phone'] ?? '').replaceAll('+40', '');
      _fullPhoneNumber = widget.userData!['phone'] ?? '';
      _dobController.text = widget.userData!['dob'] ?? widget.userData!['dateOfBirth'] ?? '';
      _selectedCity = widget.userData!['city'];
      _isTrainer = widget.userData!['isTrainer'] ?? false;
      if (_isTrainer) {
        _selectedVenueId = widget.userData!['trainerVenueId'];
        _trainerPricePerMonthController.text = (widget.userData!['trainerPricePerMonth'] ?? '').toString();
        _trainerPricePerSessionController.text = (widget.userData!['trainerPricePerSession'] ?? widget.userData!['trainerPrice'] ?? '').toString();
        
        bool hasMonth = widget.userData!['trainerPricePerMonth'] != null;
        bool hasSession = widget.userData!['trainerPricePerSession'] != null || widget.userData!['trainerPrice'] != null;
        if (hasMonth && hasSession) {
          _pricingType = 'Ambele';
        } else if (hasMonth) {
          _pricingType = 'Preț / lună';
        } else if (hasSession) {
          _pricingType = 'Preț / ședință';
        } else {
          _pricingType = 'Ambele';
        }
        _trainerIbanController.text = widget.userData!['trainerIban'] ?? '';
      }
      
      String firstName = widget.userData!['firstName'] ?? '';
      String lastName = widget.userData!['lastName'] ?? '';
      
      if (firstName.isEmpty && lastName.isEmpty) {
        String fullName = widget.userData!['fullName'] ?? widget.userData!['name'] ?? '';
        final parts = fullName.split(' ');
        if (parts.isNotEmpty) {
           firstName = parts.first;
           if (parts.length > 1) {
             lastName = parts.sublist(1).join(' ');
           }
        }
      }
      
      _firstNameController.text = firstName;
      _lastNameController.text = lastName;
      _emailController.text = widget.userData!['email'] ?? '';
    }
  }

  Future<void> _fetchVenues() async {
    try {
      final query = await FirebaseFirestore.instance.collection('venues').get();
      setState(() {
        _venuesList = query.docs.map((doc) => {'id': doc.id, 'name': doc['venueName']}).toList();
      });
    } catch (e) {
      debugPrint('Error fetching venues: $e');
    }
  }

  void _updatePasswordStrength() {
    String pass = _passwordController.text;
    if (pass.isEmpty) {
      setState(() {
        _passwordStrength = 0.0;
        _passwordStrengthText = '';
        _passwordStrengthColor = Colors.transparent;
      });
      return;
    }
    
    double strength = 0.0;
    if (pass.length >= 8) strength += 0.25;
    if (pass.contains(RegExp(r'[a-z]'))) strength += 0.25;
    if (pass.contains(RegExp(r'[A-Z]'))) strength += 0.25;
    if (pass.contains(RegExp(r'[0-9]')) || pass.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) strength += 0.25;
    
    String text;
    Color color;
    if (strength <= 0.25) {
      text = 'Slabă';
      color = Colors.red;
    } else if (strength <= 0.5) {
      text = 'Acceptabilă';
      color = Colors.orange;
    } else if (strength <= 0.75) {
      text = 'Bună';
      color = Colors.lightGreen;
    } else {
      text = 'Puternică';
      color = Colors.green;
    }
    
    setState(() {
      _passwordStrength = strength;
      _passwordStrengthText = text;
      _passwordStrengthColor = color;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _trainerPricePerMonthController.dispose();
    _trainerPricePerSessionController.dispose();
    _trainerIbanController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Te rugăm să introduci o parolă';
    }
    if (value.length < 8) {
      return 'Parola trebuie să aibă minim 8 caractere';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Parola trebuie să conțină o literă mare';
    }
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Parola trebuie să conțină un simbol';
    }
    return null;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // default age 18
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
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
      setState(() {
        _dobController.text = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final usernameStr = _usernameController.text.trim();
        
        // 0. Verificăm unicitatea username-ului
        final usernameQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: usernameStr)
            .get();
            
        if (usernameQuery.docs.isNotEmpty) {
          if (!widget.isEditMode || usernameQuery.docs.first.id != widget.userId) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Acest nume de utilizator este deja folosit.'), backgroundColor: Colors.red),
              );
            }
            setState(() => _isLoading = false);
            return;
          }
        }

        // 1. Verificăm unicitatea numărului de telefon
        final phoneQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: _fullPhoneNumber)
            .get();
            
        if (phoneQuery.docs.isNotEmpty) {
          if (!widget.isEditMode || phoneQuery.docs.first.id != widget.userId) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Acest număr de telefon este deja înregistrat.'), backgroundColor: Colors.red),
              );
            }
            setState(() => _isLoading = false);
            return;
          }
        }

        if (widget.isEditMode) {
          await _updateUser();
          return;
        }

        // 2. Inițiem verificarea telefonului (trimitere SMS)
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: _fullPhoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Nu forțăm auto-rezolvarea aici ca să nu avem duble creări, lăsăm flow-ul manual cu dialog.
          },
          verificationFailed: (FirebaseAuthException e) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Eroare SMS: ${e.message}'), backgroundColor: Colors.red),
              );
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() => _isLoading = false);
            _showOTPDialog(verificationId);
          },
          codeAutoRetrievalTimeout: (String verificationId) {},
        );

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateUser() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'username': _usernameController.text.trim(),
        'phone': _fullPhoneNumber,
        'dob': _dobController.text.trim(),
        'city': _selectedCity,
        'isTrainer': _isTrainer,
        if (_isTrainer) 'trainerVenueId': _selectedVenueId,
        if (_isTrainer) 'trainerPricePerMonth': (_pricingType == 'Ambele' || _pricingType == 'Preț / lună') ? double.tryParse(_trainerPricePerMonthController.text) : null,
        if (_isTrainer) 'trainerPricePerSession': (_pricingType == 'Ambele' || _pricingType == 'Preț / ședință') ? double.tryParse(_trainerPricePerSessionController.text) : null,
        if (_isTrainer) 'trainerIban': _trainerIbanController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil actualizat!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showOTPDialog(String verificationId) {
    final TextEditingController otpController = TextEditingController();
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Verificare SMS', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Am trimis un cod prin SMS. Te rugăm să-l introduci mai jos pentru a-ți confirma numărul.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Cod format din 6 cifre',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDialogLoading ? null : () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading
                      ? null
                      : () async {
                          if (otpController.text.length != 6) return;
                          setDialogState(() => isDialogLoading = true);

                          try {
                            // Creăm credențialul din codul SMS
                            PhoneAuthCredential phoneCredential = PhoneAuthProvider.credential(
                              verificationId: verificationId,
                              smsCode: otpController.text.trim(),
                            );

                            // Creăm contul cu Email/Parolă
                            final UserCredential credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                              email: _emailController.text.trim(),
                              password: _passwordController.text,
                            );

                            final User? user = credential.user;

                            if (user != null) {
                              // Asociem numărul de telefon contului creat
                              await user.linkWithCredential(phoneCredential);

                              // Trimitem email-ul de confirmare
                              await user.sendEmailVerification();

                              // Salvăm datele în Firestore
                              await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                                'uid': user.uid,
                                'username': _usernameController.text.trim(),
                                'firstName': _firstNameController.text.trim(),
                                'lastName': _lastNameController.text.trim(),
                                'email': _emailController.text.trim(),
                                'phone': _fullPhoneNumber,
                                'dob': _dobController.text.trim(),
                                'city': _selectedCity ?? '',
                                'pingPongLevel': 'Începător',
                                'matchesPlayed': 0,
                                'rating': 0,
                                'isTrainer': _isTrainer,
                                'trainerVenueId': _isTrainer ? _selectedVenueId : null,
                                'trainerPricePerMonth': _isTrainer ? ((_pricingType == 'Ambele' || _pricingType == 'Preț / lună') ? double.tryParse(_trainerPricePerMonthController.text) : null) : null,
                                'trainerPricePerSession': _isTrainer ? ((_pricingType == 'Ambele' || _pricingType == 'Preț / ședință') ? double.tryParse(_trainerPricePerSessionController.text) : null) : null,
                                'trainerIban': _isTrainer ? _trainerIbanController.text.trim() : null,
                                'createdAt': FieldValue.serverTimestamp(),
                              });

                              if (mounted) {
                                Navigator.pop(context); // Închidem dialogul
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cont creat! Am trimis un link de confirmare pe email.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AvatarScreen()),
                                );
                              }
                            }
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() => isDialogLoading = false);
                            String msg = 'Eroare la verificare.';
                            if (e.code == 'invalid-verification-code') {
                              msg = 'Codul SMS este incorect.';
                            } else if (e.code == 'credential-already-in-use') {
                              msg = 'Acest număr de telefon este asociat altui cont.';
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg), backgroundColor: Colors.red),
                            );
                          } catch (e) {
                            setDialogState(() => isDialogLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                  child: isDialogLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Confirmă'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isEditMode ? 'Editează Cont' : 'Creează Cont',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isEditMode ? 'Modifică detaliile utilizatorului.' : 'Completează detaliile de mai jos pentru a te alătura.',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),

                // Nume si Prenume
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'Prenume'),
                        validator: (value) => value!.isEmpty ? 'Necesar' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Nume'),
                        validator: (value) => value!.isEmpty ? 'Necesar' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Username
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nume de utilizator',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value!.isEmpty ? 'Introduceți un nume de utilizator' : null,
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Introduceți adresa de email';
                    if (!value.contains('@')) return 'Email invalid';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Telefon
                IntlPhoneField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Număr de telefon',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  initialCountryCode: 'RO',
                  onChanged: (phone) {
                    _fullPhoneNumber = phone.completeNumber;
                  },
                ),
                const SizedBox(height: 16),

                // Data de Nastere
                TextFormField(
                  controller: _dobController,
                  readOnly: true,
                  onTap: () => _selectDate(context),
                  decoration: const InputDecoration(
                    labelText: 'Data de naștere',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  validator: (value) => value!.isEmpty ? 'Necesar' : null,
                ),
                const SizedBox(height: 16),

                // Oraș
                CitySelectorField(
                  labelText: 'Orașul tău',
                  selectedCity: _selectedCity,
                  cityOptions: romanianCities,
                  onCitySelected: (city) => setState(() => _selectedCity = city),
                  validator: (val) => (val == null || val.isEmpty) ? 'Selectează orașul tău' : null,
                ),
                const SizedBox(height: 16),

                if (!widget.isEditMode) ...[
                  // Parola
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
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  if (_passwordStrengthText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _passwordStrength,
                              backgroundColor: Colors.grey[800],
                              color: _passwordStrengthColor,
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _passwordStrengthText,
                          style: TextStyle(
                            color: _passwordStrengthColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Confirmare Parola
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirmare parolă',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Confirmă parola';
                      }
                      if (value != _passwordController.text) {
                        return 'Parolele nu coincid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                SwitchListTile(
                  title: const Text('Sunt Antrenor Personal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Bifează dacă oferi servicii de antrenor la o sală', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _isTrainer,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (val) => setState(() => _isTrainer = val),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_isTrainer) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedVenueId,
                    dropdownColor: const Color(0xFF131A2A),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Selectează Sala',
                      prefixIcon: Icon(Icons.business),
                    ),
                    items: _venuesList.map((v) {
                      return DropdownMenuItem<String>(
                        value: v['id'],
                        child: Text(v['name']),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedVenueId = val),
                    validator: (val) => _isTrainer && val == null ? 'Selectează sala unde antrenezi' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _pricingType,
                    dropdownColor: const Color(0xFF131A2A),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Tip Tarif Antrenor',
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: ['Ambele', 'Preț / lună', 'Preț / ședință'].map((type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _pricingType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_pricingType == 'Ambele' || _pricingType == 'Preț / lună')
                        Expanded(
                          child: TextFormField(
                            controller: _trainerPricePerMonthController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Preț / lună (RON)',
                              prefixIcon: Icon(Icons.monetization_on_outlined),
                            ),
                          ),
                        ),
                      if (_pricingType == 'Ambele')
                        const SizedBox(width: 16),
                      if (_pricingType == 'Ambele' || _pricingType == 'Preț / ședință')
                        Expanded(
                          child: TextFormField(
                            controller: _trainerPricePerSessionController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Preț / ședință',
                              prefixIcon: Icon(Icons.monetization_on_outlined),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _trainerIbanController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'IBAN pentru plată (Opțional)',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 32),

                // Buton Inregistrare cu stare de loading
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(widget.isEditMode ? 'SALVEAZĂ MODIFICĂRI' : 'ÎNREGISTREAZĂ-TE'),
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