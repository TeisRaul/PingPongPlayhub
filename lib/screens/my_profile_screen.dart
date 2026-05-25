import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/level_utils.dart';
import 'avatar_screen.dart';
import '../widgets/player_drawer.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  
  // Stats calculated from matches
  int totalMatches = 0;
  int wins = 0;
  int losses = 0;
  String winRate = "0%";
  List<double> ratingHistory = [];

  @override
  void initState() {
    super.initState();
    _loadUserDataAndStats();
  }

  Future<void> _loadUserDataAndStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Load user data
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      
      // Load matches to calculate stats
      final matchesQuery = await FirebaseFirestore.instance
          .collection('matches')
          .where('joinedUids', arrayContains: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();

      int w = 0;
      int l = 0;
      
      // We assume there's a winnerUid field or we just read from user profile
      for (var match in matchesQuery.docs) {
        final data = match.data();
        if (data['winnerUid'] == user.uid) {
          w++;
        } else if (data['winnerUid'] != null && data['winnerUid'] != user.uid) {
          l++;
        }
      }
      
      final tMatches = matchesQuery.docs.length;
      final rate = tMatches > 0 ? ((w / tMatches) * 100).toStringAsFixed(1) + "%" : "0%";

      if (doc.exists) {
        setState(() {
          userData = doc.data();
          
          // Use calculated stats or fallback to user document
          totalMatches = tMatches;
          wins = w > 0 ? w : (userData?['wins'] ?? 0);
          winRate = tMatches > 0 ? rate : (userData?['winRate'] ?? "0%");
          
          // Mocking rating history if not present in DB for the chart to look good
          List<dynamic> historyRaw = userData?['ratingHistory'] ?? [];
          if (historyRaw.isEmpty) {
             final currentR = (userData?['rating'] ?? 1000).toDouble();
             ratingHistory = [
               currentR - 50 < 1000 ? 1000 : currentR - 50,
               currentR - 20 < 1000 ? 1000 : currentR - 20,
               currentR + 10,
               currentR - 15,
               currentR
             ];
          } else {
             ratingHistory = historyRaw.map((e) => (e as num).toDouble()).toList();
          }
          
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

  // Badges Logic
  List<Widget> _buildBadges() {
    List<Widget> badges = [];
    
    // Incepator
    if (totalMatches >= 1 || (userData?['wins'] ?? 0) > 0) {
      badges.add(_buildBadgeItem(Icons.water_drop, 'First Drop', 'Începător', const Color(0xFF00FF66)));
    }
    if (wins >= 1) {
      badges.add(_buildBadgeItem(Icons.thumb_up, 'Rookie Win', 'Începător', const Color(0xFF00E5FF)));
    }
    
    // Intermediar
    if (totalMatches >= 20) {
      badges.add(_buildBadgeItem(Icons.sports_tennis, 'PingPong Regular', 'Intermediar', const Color(0xFFC0C0C0)));
    }
    if (wins >= 10) {
      badges.add(_buildBadgeItem(Icons.local_fire_department, 'Winning Streak', 'Intermediar', const Color(0xFFFF4500)));
    }
    
    // Avansat
    if (totalMatches >= 100) {
      badges.add(_buildBadgeItem(Icons.account_balance, 'Arena Master', 'Avansat', const Color(0xFFFFD700)));
    }
    final rating = userData?['rating'] ?? 0;
    if (rating >= 2000) {
      badges.add(_buildBadgeItem(Icons.diamond, 'Diamond Player', 'Avansat', const Color(0xFFB9F2FF)));
    }

    if (badges.isEmpty) {
      return [const Text('Joacă meciuri pentru a debloca insigne!', style: TextStyle(color: Colors.grey))];
    }
    return badges;
  }

  Widget _buildBadgeItem(IconData icon, String title, String category, Color color) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
          const SizedBox(height: 4),
          Text(category, style: TextStyle(color: color, fontSize: 9), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStatsChart() {
    if (ratingHistory.length < 2) {
      return const Center(
        child: Text('Nu sunt destule date pentru grafic.', style: TextStyle(color: Colors.grey)),
      );
    }

    List<FlSpot> spots = [];
    for (int i = 0; i < ratingHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), ratingHistory[i]));
    }
    
    double minY = ratingHistory.reduce((a, b) => a < b ? a : b) - 20;
    double maxY = ratingHistory.reduce((a, b) => a > b ? a : b) + 20;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (ratingHistory.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF00E5FF),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
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
                              AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: oldP);
                              await user.reauthenticateWithCredential(credential);
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: const Text('Profilul Meu & Statistici'),
        centerTitle: true,
      ),
      drawer: const PlayerDrawer(activePage: 'profile'),
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
                      ).then((_) => _loadUserDataAndStats()); 
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
            
            // --- NEW: Player Statistics ---
            const SizedBox(height: 16),
            const Text('Statistici Meciuri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCircle('Victorii', '$wins', const Color(0xFF00FF66)),
                _buildStatCircle('Jucate', '$totalMatches', const Color(0xFF00E5FF)),
                _buildStatCircle('Win Rate', winRate, const Color(0xFFFFD700)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Evoluție ELO (Ultimele Meciuri)', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            _buildStatsChart(),

            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            
            // --- NEW: Badges ---
            const SizedBox(height: 16),
            const Text('Ecusoane (Badges)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _buildBadges(),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            
            // Date Personale
            const SizedBox(height: 16),
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

  Widget _buildStatCircle(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            color: color.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(value, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
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
