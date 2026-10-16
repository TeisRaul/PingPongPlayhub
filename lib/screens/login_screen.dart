import 'package:flutter/material.dart';
import '../l10n/app_locales.dart';
import '../l10n/strings.dart';
import '../widgets/language_picker.dart';
import '../widgets/theme_picker.dart';
import '../services/account_lookup.dart';
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
import '../theme/app_theme.dart';
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
  // La pornire verificăm dacă există deja o sesiune (ex. după reîncărcarea paginii sau întoarcerea de la plată).
  bool _checkingSession = true;

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AppLocales.current.addListener(_onLangChanged);
    _restoreSession();
  }

  /// Firebase păstrează autentificarea (pe web, în browser). Dacă utilizatorul e deja logat și are
  /// profil (jucător sau sală), intră direct în aplicație, fără să se logheze din nou.
  Future<void> _restoreSession() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      user ??= await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (user != null) {
        final db = FirebaseFirestore.instance;
        final results = await Future.wait([
          db.collection('users').doc(user.uid).get(),
          db.collection('venues').doc(user.uid).get(),
        ]);
        if (results.any((d) => d.exists)) {
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          return;
        }
      }
    } catch (_) {
      // Fără rețea sau altă eroare: arătăm formularul de autentificare.
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  @override
  void dispose() {
    AppLocales.current.removeListener(_onLangChanged);
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
          SnackBar(content: Text(tr('auth.err_google', {'error': '$e'})), backgroundColor: Colors.red),
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
          final OAuthCredential credential = FacebookAuthProvider.credential(accessToken.tokenString);
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
          SnackBar(content: Text(tr('auth.err_facebook', {'error': '$e'})), backgroundColor: Colors.red),
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
        SnackBar(content: Text(tr('auth.fill_both')), backgroundColor: Colors.red),
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
        final foundEmail = await AccountLookup.emailForUsername(input);

        if (foundEmail != null) {
          emailToLogin = foundEmail;
        } else {
          throw FirebaseAuthException(code: 'user-not-found', message: 'unknown-username');
        }
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailToLogin,
        password: password,
      );
      // Conturile mai vechi primesc acum înregistrarea pentru autentificarea cu nume de utilizator.
      await AccountLookup.ensureForCurrentUser();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = tr('auth.failed');
      if (e.code == 'user-not-found' || e.message == 'unknown-username') {
        errorMessage = tr('auth.user_not_found');
      } else if (e.code == 'wrong-password') {
        errorMessage = tr('auth.wrong_password');
      } else if (e.code == 'invalid-email') {
        errorMessage = tr('auth.invalid_format');
      } else if (e.code == 'invalid-credential') {
        errorMessage = tr('auth.invalid_credential');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('auth.err', {'error': '$e'})), backgroundColor: Colors.red),
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
    if (_checkingSession) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [ThemePickerButton(), LanguagePickerButton()]),
              ),
              const SizedBox(height: 24),
              // App Logo / Title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sports_soccer, size: 45, color: AppColors.accent),
                  SizedBox(width: 12),
                  Icon(Icons.sports_tennis, size: 65, color: AppColors.accent),
                  SizedBox(width: 12),
                  Icon(Icons.sports_basketball, size: 45, color: AppColors.accent),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Playhub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('auth.welcome'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 48),

              // Email/Username Input
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: InputDecoration(
                  labelText: tr('auth.email_or_user'),
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
                  labelText: tr('auth.password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.muted,
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
                  child: Text(tr('auth.forgot'), style: TextStyle(color: AppColors.accent)),
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
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.text)) 
                    : Text(tr('auth.login')),
              ),
              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      tr('auth.or'),
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ],
              ),
              const SizedBox(height: 24),

              // Social Login Buttons
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithGoogle,
                icon: FaIcon(FontAwesomeIcons.google, color: AppColors.text),
                label: Text(tr('auth.google')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.muted),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithFacebook,
                icon: const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2)),
                label: Text(tr('auth.facebook')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.muted),
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
                  Text(
                    tr('auth.no_account'),
                    style: TextStyle(color: AppColors.muted),
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
                      foregroundColor: AppColors.accent,
                    ),
                    child: Text(tr('auth.create_account')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Venue Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tr('auth.venue_owner'),
                    style: TextStyle(color: AppColors.muted),
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
                      foregroundColor: AppColors.bad, // Vibrant neon pink/magenta
                    ),
                    child: Text(tr('auth.venue_register')),
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