import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'avatar_screen.dart';

class SignupScreen extends StatefulWidget {
  final String? initialFirstName;
  final String? initialLastName;
  final String? initialEmail;

  const SignupScreen({
    super.key, 
    this.initialFirstName, 
    this.initialLastName, 
    this.initialEmail
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final _firstNameController = TextEditingController(text: widget.initialFirstName ?? '');
  late final _lastNameController = TextEditingController(text: widget.initialLastName ?? '');
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');
  
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  String _fullPhoneNumber = '';
  double _passwordStrength = 0.0;
  String _passwordStrengthText = '';
  Color _passwordStrengthColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordStrength);
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  // Modificat pentru a fi asincron (async)
  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // 1. Creăm contul în Firebase Auth
        final UserCredential credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        final User? user = credential.user;

        if (user != null) {
          // 2. Salvăm restul datelor în Firestore sub același UID
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'firstName': _firstNameController.text.trim(),
            'lastName': _lastNameController.text.trim(),
            'email': _emailController.text.trim(),
            'phone': _fullPhoneNumber,
            'dob': _dobController.text.trim(),
            'pingPongLevel': 'Începător', // Valoare default pentru matchmaking
            'matchesPlayed': 0,
            'rating': 1000,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // 3. Dacă totul e ok, navigăm către ecranul de login
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cont creat cu succes! Te poți autentifica acum.'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context); // Ne întoarcem la LoginScreen
          }
        }
      } on FirebaseAuthException catch (e) {
        // Tratăm erorile specifice Firebase Auth (ex: email deja folosit)
        String errorMessage = 'A apărut o eroare la înregistrare.';
        if (e.code == 'email-already-in-use') {
          errorMessage = 'Acest email este deja asociat unui cont.';
        } else if (e.code == 'invalid-email') {
          errorMessage = 'Formatul email-ului este invalid.';
        }

        print('====================================');
        print('EROARE REALA FIREBASE: $e');
        print('====================================');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        // Prindem orice altă eroare
        print('====================================');
        print('EROARE GENERALA: $e');
        print('====================================');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
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
                const Text(
                  'Creează Cont',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Completează detaliile de mai jos pentru a te alătura.',
                  style: TextStyle(
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
                      : const Text('ÎNREGISTREAZĂ-TE'),
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