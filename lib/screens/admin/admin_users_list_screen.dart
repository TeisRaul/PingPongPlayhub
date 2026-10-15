import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_matches_list_screen.dart';
import '../signup_screen.dart';
import '../../theme/app_theme.dart';

/// Numele afișat: fullName, altfel prenume + nume, altfel username.
String _displayName(Map<String, dynamic> data, {String fallback = 'Fără nume'}) {
  String clean(dynamic v) => (v ?? '').toString().trim();
  final full = clean(data['fullName']);
  if (full.isNotEmpty) return full;
  final both = '${clean(data['firstName'])} ${clean(data['lastName'])}'.trim();
  if (both.isNotEmpty) return both;
  final user = clean(data['username']);
  if (user.isNotEmpty) return user;
  final legacy = clean(data['name']);
  if (legacy.isNotEmpty) return legacy;
  return fallback;
}

class AdminUsersListScreen extends StatefulWidget {
  const AdminUsersListScreen({super.key});

  @override
  State<AdminUsersListScreen> createState() => _AdminUsersListScreenState();
}

class _AdminUsersListScreenState extends State<AdminUsersListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Gestiune Utilizatori', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Caută după nume sau email...',
                hintStyle: TextStyle(color: AppColors.muted),
                prefixIcon: Icon(Icons.search, color: AppColors.muted),
                filled: true,
                fillColor: AppColors.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text('Niciun utilizator înregistrat.', style: TextStyle(color: AppColors.muted)),
            );
          }

          final users = snapshot.data!.docs.where((doc) {
            if (_searchQuery.isEmpty) return true;
            final data = doc.data() as Map<String, dynamic>;
            final name = _displayName(data, fallback: '').toLowerCase();
            final email = (data['email'] ?? '').toString().toLowerCase();
            final q = _searchQuery.toLowerCase();
            return name.contains(q) || email.contains(q);
          }).toList();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = users[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = _displayName(data);
              final email = data['email'] ?? 'Fără email';
              final phone = data['phone'] ?? 'Fără telefon';

              return Card(
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.card2,
                    child: Icon(Icons.person, color: AppColors.accent),
                  ),
                  title: Text(name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  subtitle: Text('$email\n$phone', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  isThreeLine: true,
                  trailing: Icon(Icons.arrow_forward_ios, color: AppColors.muted, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminUserDetailScreen(
                          userId: doc.id,
                          userData: data,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminUserDetailScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const AdminUserDetailScreen({super.key, required this.userId, required this.userData});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _deleteUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Ștergere Utilizator', style: TextStyle(color: AppColors.text)),
        content: Text('Atenție! Această acțiune va șterge profilul public al utilizatorului din aplicație. Ești sigur?', style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Șterge', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).delete();
      if (mounted) {
        Navigator.pop(context); // back to list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilizator șters!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPasswordReset(String? userEmail) async {
    final email = userEmail?.toString().trim() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilizatorul nu are o adresă de email validă.'), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email de resetare trimis la $email!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la trimiterea email-ului: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Detalii Utilizator', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        actions: [
          if (widget.userData['email'] != 'teisraul@yahoo.co.uk')
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isLoading ? null : _deleteUser,
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text('Utilizatorul nu mai există', style: TextStyle(color: AppColors.muted)),
            );
          }

          final freshData = snapshot.data!.data() as Map<String, dynamic>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.card2,
                  child: Icon(Icons.person, color: AppColors.accent, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  _displayName(freshData),
                  style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                if (freshData['email'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    freshData['email'],
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminMatchesListScreen(
                            initialSearchQuery: _displayName(freshData, fallback: ''),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Vezi Istoric Meciuri'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.text,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppColors.muted),
                    ),
                  ),
                ),
                if (freshData['email'] != 'teisraul@yahoo.co.uk') ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _sendPasswordReset(freshData['email']),
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Trimite Email Resetare Parolă', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.orangeAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _deleteUser,
                      icon: const Icon(Icons.delete),
                      label: const Text('Șterge Utilizator', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SignupScreen(
                            isEditMode: true,
                            userId: widget.userId,
                            userData: freshData,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_document),
                    label: const Text('Editează Utilizator Complet (Formular)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: Colors.amberAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.amberAccent),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
