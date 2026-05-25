import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Pentru kIsWeb
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'signup_screen.dart';
import 'venue_signup_screen.dart';
import 'google_login_stub.dart' if (dart.library.io) 'google_login_mobile.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Funcția pentru Autentificare cu Google ---
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? userCredential;

      if (kIsWeb) {
        // Metoda recomandată pentru Firebase pe Web (Chrome)
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        // Metoda pentru Mobile (Android / iOS)
        userCredential = await signInWithGoogleMobile();
        if (userCredential == null) {
          setState(() => _isLoading = false);
          return; // Anulat
        }
      }

      final User? user = userCredential.user;

      if (user != null) {
        // 5. Verificăm dacă utilizatorul are deja profil în baza noastră de date
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (mounted) {
          if (userDoc.exists) {
            // Caz A: Are deja cont complet. Îl trimitem direct în aplicație.
            print("Utilizator existent. Navigare către Home.");
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          } else {
            // Caz B: Este prima dată. Extragem datele și îl trimitem la Signup
            
            // Spargem "John Doe" în "John" și "Doe"
            List<String> nameParts = (user.displayName ?? '').split(' ');
            String prefilledFirstName = nameParts.isNotEmpty ? nameParts.first : '';
            String prefilledLastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
            String prefilledEmail = user.email ?? '';

            // Trimitem datele către SignupScreen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SignupScreen(
                  initialFirstName: prefilledFirstName,
                  initialLastName: prefilledLastName,
                  initialEmail: prefilledEmail,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la logarea cu Google: $e'), backgroundColor: Colors.red),
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

  // --- Funcția pentru Autentificare cu Facebook ---
  Future<void> _signInWithFacebook() async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? userCredential;

      if (kIsWeb) {
        final FacebookAuthProvider facebookProvider = FacebookAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(facebookProvider);
      } else {
        // Mobile Real Facebook Login
        final LoginResult result = await FacebookAuth.instance.login(permissions: ['public_profile', 'email']);
        
        if (result.status == LoginStatus.success) {
          final AccessToken accessToken = result.accessToken!;
          final OAuthCredential credential = FacebookAuthProvider.credential(accessToken.token);
          userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        } else {
          setState(() => _isLoading = false);
          return;
        }
      }

      final User? user = userCredential.user;

      if (user != null) {
        // Verificăm dacă utilizatorul are deja profil în baza noastră de date
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (mounted) {
          if (userDoc.exists) {
            print("Utilizator existent. Navigare către Home.");
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          } else {
            // Trimitem datele către SignupScreen
            String prefilledFirstName = '';
            String prefilledLastName = '';
            String prefilledEmail = user.email ?? '';

            if (user.displayName != null && user.displayName!.isNotEmpty) {
              List<String> nameParts = user.displayName!.split(' ');
              prefilledFirstName = nameParts[0];
              if (nameParts.length > 1) {
                prefilledLastName = nameParts.sublist(1).join(' ');
              }
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SignupScreen(
                  initialFirstName: prefilledFirstName,
                  initialLastName: prefilledLastName,
                  initialEmail: prefilledEmail,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la logarea cu Facebook: $e'), backgroundColor: Colors.red),
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

  // _showFacebookSandboxSimulator removed

  // --- Funcția pentru Autentificare Email/Parolă (de bază) ---
  Future<void> _handleEmailLogin() async {
    final input = _emailController.text.trim();
    final password = _passwordController.text;

    if (input.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te rugăm să completezi ambele câmpuri'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String emailToLogin = input;

      // Dacă nu conține '@', presupunem că e username și căutăm emailul
      if (!input.contains('@')) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: input)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          emailToLogin = querySnapshot.docs.first.data()['email'] as String;
        } else {
          throw FirebaseAuthException(code: 'user-not-found', message: 'Nume de utilizator inexistent.');
        }
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailToLogin,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Autentificare eșuată.';
      if (e.code == 'user-not-found' || e.message == 'Nume de utilizator inexistent.') {
        errorMessage = 'Utilizatorul nu a fost găsit.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Parola este incorectă.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Format invalid.';
      } else if (e.code == 'invalid-credential') {
        errorMessage = 'Date de autentificare incorecte.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
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
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // App Logo / Title
              const Icon(
                Icons.sports_tennis,
                size: 80,
                color: Color(0xFF00E5FF),
              ),
              const SizedBox(height: 16),
              const Text(
                'PingPong Playhub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bun venit! Autentifică-te pentru a juca.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),

              // Email/Username Input
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Email sau Nume de utilizator',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              // Password Input
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isLoading ? null : _handleEmailLogin(),
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
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
                  },
                  child: const Text('Ai uitat parola?', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ),
              const SizedBox(height: 16),

              // Login Button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleEmailLogin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white)) 
                    : const Text('LOG IN'),
              ),
              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[800])),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'SAU',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[800])),
                ],
              ),
              const SizedBox(height: 24),

              // Social Login Buttons
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithGoogle,
                icon: const FaIcon(FontAwesomeIcons.google, color: Colors.white),
                label: const Text('Logează-te cu Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithFacebook,
                icon: const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2)),
                label: const Text('Logează-te cu Facebook'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Nu ai un cont? ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignupScreen(), // Fără parametri inițiali pentru fluxul manual
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                    ),
                    child: const Text('Creează cont nou'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Venue Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Ești proprietar de sală? ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const VenueSignupScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF0055), // Vibrant neon pink/magenta
                    ),
                    child: const Text('Înregistrează-te'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}