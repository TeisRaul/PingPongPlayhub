import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/level_utils.dart';
import 'avatar_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          userData = doc.data();
          _isLoading = false;
        });
      }
    }
  }

  ImageProvider? _getAvatarProvider(String? url) {
    if (url == null) return null;
    if (url.startsWith('data:image')) {
      return MemoryImage(base64Decode(url.split(',').last));
    }
    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    return NetworkImage(url);
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Schimbă Parola', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parola veche'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parola nouă'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Parola nouă trebuie să aibă minim 8 caractere, o literă mare și un simbol.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final oldP = oldPassCtrl.text;
                          final newP = newPassCtrl.text;

                          if (newP.length < 8 || !newP.contains(RegExp(r'[A-Z]')) || !newP.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola nouă nu respectă condițiile!'), backgroundColor: Colors.red));
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            User? user = FirebaseAuth.instance.currentUser;
                            if (user != null && user.email != null) {
                              // Reautentificare
                              AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: oldP);
                              await user.reauthenticateWithCredential(credential);

                              // Schimbare
                              await user.updatePassword(newP);

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola a fost schimbată!'), backgroundColor: Colors.green));
                              }
                            }
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() => isSaving = false);
                            String msg = 'Eroare la schimbare.';
                            if (e.code == 'wrong-password' || e.code == 'invalid-credential') msg = 'Parola veche este incorectă.';
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
                          }
                        },
                  child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Salvează'),
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    final rating = userData?['rating'] ?? 0;
    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];
    final int currentPoints = levelDetails['currentPointsInLevel'];
    final int pointsToNext = levelDetails['pointsToNextLevel'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profilul Meu'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar & Level Section
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[800],
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 6,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AvatarScreen()),
                      ).then((_) => _loadUserData()); // Refresh on return
                    },
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[700],
                      backgroundImage: _getAvatarProvider(userData?['avatarUrl']),
                      child: userData?['avatarUrl'] == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E5FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit, color: Colors.black, size: 20),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              levelName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
            ),
            const SizedBox(height: 8),
            Text(
              '$currentPoints / ${currentPoints + pointsToNext} Puncte (Rating total: $rating)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),

            // Date Personale
            const Text('Date Personale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            _buildProfileRow(Icons.person_outline, 'Nume de utilizator', userData?['username'] ?? '-'),
            _buildProfileRow(Icons.badge_outlined, 'Nume complet', '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'),
            _buildProfileRow(Icons.email_outlined, 'Email', userData?['email'] ?? '-'),
            _buildProfileRow(Icons.phone_outlined, 'Telefon', userData?['phone'] ?? '-'),
            _buildProfileRow(Icons.calendar_today_outlined, 'Data Nașterii', userData?['dob'] ?? '-'),
            
            const SizedBox(height: 32),
            
            OutlinedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Schimbă Parola'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
