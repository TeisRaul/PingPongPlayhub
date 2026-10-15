import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/strings.dart';
import '../utils/hour_utils.dart';
import '../utils/level_utils.dart';
import '../utils/match_stats.dart';
import 'avatar_screen.dart';
import 'my_stats_screen.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  bool _isPrivate = false;
  
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
      
      for (var match in matchesQuery.docs) {
        if (didUserWinMatch(match.data(), user.uid)) {
          w++;
        }
      }
      
      final tMatches = matchesQuery.docs.length;

      // Evoluția reală a ratingului, din meciurile care au salvat `ratingChanges`.
      final realHistory = <MapEntry<DateTime, List<int>>>[];
      for (var match in matchesQuery.docs) {
        final m = match.data();
        final rc = m['ratingChanges'];
        if (rc is! Map || rc[user.uid] is! Map) continue;
        try {
          final when = dateAtHour((m['date'] ?? '').toString(), m['startHour']);
          realHistory.add(MapEntry(when, [
            (rc[user.uid]['before'] as num).toInt(),
            (rc[user.uid]['after'] as num).toInt(),
          ]));
        } catch (_) {}
      }
      realHistory.sort((a, b) => a.key.compareTo(b.key));
      final rate = formatWinRate(w, tMatches);

      if (doc.exists) {
        setState(() {
          userData = doc.data();
          _isPrivate = userData?['isPrivate'] ?? false;
          
          // Use calculated stats or fallback to user document
          totalMatches = tMatches;
          wins = w > 0 ? w : (userData?['wins'] ?? 0);
          winRate = tMatches > 0 ? rate : (userData?['winRate'] ?? "0%");
          
          // Mocking rating history if not present in DB for the chart to look good
          List<dynamic> historyRaw = userData?['ratingHistory'] ?? [];
          if (realHistory.isNotEmpty) {
            ratingHistory = [
              realHistory.first.value[0].toDouble(),
              for (final h in realHistory) h.value[1].toDouble(),
            ];
          } else if (historyRaw.isEmpty) {
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
      badges.add(_buildBadgeItem(Icons.water_drop, 'First Drop', 'Începător', AppColors.good));
    }
    if (wins >= 1) {
      badges.add(_buildBadgeItem(Icons.thumb_up, 'Rookie Win', 'Începător', AppColors.accent));
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
      badges.add(_buildBadgeItem(Icons.account_balance, 'Arena Master', 'Avansat', AppColors.gold));
    }
    final rating = userData?['rating'] ?? 0;
    if (rating >= 2000) {
      badges.add(_buildBadgeItem(Icons.diamond, 'Diamond Player', 'Avansat', const Color(0xFFB9F2FF)));
    }

    if (badges.isEmpty) {
      return [Text('Joacă meciuri pentru a debloca insigne!', style: TextStyle(color: AppColors.muted))];
    }
    return badges;
  }

  Widget _buildBadgeItem(IconData icon, String title, String category, Color color) {
    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
          const SizedBox(height: 4),
          Text(category, style: TextStyle(color: color, fontSize: 9), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStatsChart() {
    if (ratingHistory.length < 2) {
      return Center(
        child: Text('Nu sunt destule date pentru grafic.', style: TextStyle(color: AppColors.muted)),
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
              color: AppColors.accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withValues(alpha: 0.1),
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
              backgroundColor: AppColors.card,
              title: Text('Schimbă Parola', style: TextStyle(color: AppColors.text)),
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
                  Text(
                    'Parola nouă trebuie să aibă minim 8 caractere, o literă mare și un simbol.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
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
                          if (oldPassCtrl.text.isEmpty || newPassCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completati ambele campuri!'), backgroundColor: Colors.red));
                            return;
                          }
                          final newP = newPassCtrl.text;
                          if (newP.length < 8 ||
                              !newP.contains(RegExp(r'[A-Z]')) ||
                              !newP.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola nouă trebuie să aibă minim 8 caractere, o literă mare și un simbol.'), backgroundColor: Colors.red));
                            return;
                          }
                          
                          setDialogState(() => isSaving = true);
                          try {
                            final authUser = FirebaseAuth.instance.currentUser;
                            if (authUser == null || authUser.email == null) {
                              throw Exception('Nu ești autentificat cu email și parolă.');
                            }
                            final credential = EmailAuthProvider.credential(email: authUser.email!, password: oldPassCtrl.text);
                            await authUser.reauthenticateWithCredential(credential);
                            await authUser.updatePassword(newP);
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola a fost schimbată!'), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            final wrongOld = e is FirebaseAuthException && (e.code == 'wrong-password' || e.code == 'invalid-credential');
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wrongOld ? 'Parola veche este incorectă.' : 'Eroare: $e'), backgroundColor: Colors.red));
                          } finally {
                            if (mounted) setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.text, strokeWidth: 2))
                      : Text('Salvează', style: TextStyle(color: AppColors.accent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFollowRequestsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Cereri de urmărire', style: TextStyle(color: AppColors.text)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: AppColors.accent));
                
                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final followRequests = List<String>.from(data['followRequests'] ?? []);
                
                if (followRequests.isEmpty) {
                  return Center(child: Text('Nu ai nicio cerere de urmărire.', style: TextStyle(color: AppColors.muted)));
                }

                return ListView.builder(
                  itemCount: followRequests.length,
                  itemBuilder: (context, index) {
                    final reqUid = followRequests[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(reqUid).get(),
                      builder: (context, userSnap) {
                        if (!userSnap.hasData) return ListTile(title: Text('Se încarcă...', style: TextStyle(color: AppColors.muted)));
                        final reqData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                        final name = reqData['username'] ?? 'Utilizator necunoscut';
                        
                        return ListTile(
                          title: Text(name, style: TextStyle(color: AppColors.text)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () async {
                                  final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUserUid != null) {
                                    final batch = FirebaseFirestore.instance.batch();
                                    final targetRef = FirebaseFirestore.instance.collection('users').doc(currentUserUid);
                                    final reqRef = FirebaseFirestore.instance.collection('users').doc(reqUid);
                                    
                                    // Remove from requests, add to followers
                                    batch.update(targetRef, {
                                      'followRequests': FieldValue.arrayRemove([reqUid]),
                                      'followers': FieldValue.arrayUnion([reqUid]),
                                    });
                                    // Add to requesters following
                                    batch.update(reqRef, {
                                      'following': FieldValue.arrayUnion([currentUserUid]),
                                    });
                                    
                                    await batch.commit();
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () async {
                                  final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUserUid != null) {
                                    await FirebaseFirestore.instance.collection('users').doc(currentUserUid).update({
                                      'followRequests': FieldValue.arrayRemove([reqUid]),
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Închide', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
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
            icon: Icon(Icons.menu, color: AppColors.accent),
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
                      backgroundColor: AppColors.border,
                      color: AppColors.accent,
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
                      backgroundColor: AppColors.border700,
                      backgroundImage: _getAvatarProvider(userData?['avatarUrl']),
                      child: userData?['avatarUrl'] == null ? Icon(Icons.person, size: 50, color: AppColors.text) : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
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
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.accent),
            ),
            const SizedBox(height: 8),
            Text(
              '$currentPoints / ${currentPoints + pointsToNext} Puncte (Rating total: $rating)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            
            const SizedBox(height: 32),
            Divider(color: AppColors.muted),
            
            // --- NEW: Player Statistics ---
            const SizedBox(height: 16),
            Text('Statistici Meciuri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCircle('Victorii', '$wins', AppColors.good),
                _buildStatCircle('Jucate', '$totalMatches', AppColors.accent),
                _buildStatCircle('Win Rate', winRate, AppColors.gold),
              ],
            ),
            const SizedBox(height: 24),
            Text('Evoluție ELO (Ultimele Meciuri)', style: TextStyle(fontSize: 14, color: AppColors.muted)),
            const SizedBox(height: 16),
            _buildStatsChart(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: Text(tr('stats.full_btn')),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyStatsScreen())),
              ),
            ),

            const SizedBox(height: 32),
            Divider(color: AppColors.muted),
            
            // --- NEW: Badges ---
            const SizedBox(height: 16),
            Text('Ecusoane (Badges)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _buildBadges(),
              ),
            ),

            const SizedBox(height: 32),
            Divider(color: AppColors.muted),
            
            const SizedBox(height: 16),
            Text('Setări Confidențialitate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
            SwitchListTile(
              title: Text('Cont Privat', style: TextStyle(color: AppColors.text)),
              subtitle: Text('Doar urmăritorii pot vedea postările tale.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              activeColor: AppColors.accent,
              value: _isPrivate,
              onChanged: (val) async {
                setState(() => _isPrivate = val);
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'isPrivate': val});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(val ? 'Contul este acum privat.' : 'Contul este acum public.'),
                      backgroundColor: Colors.green,
                    ));
                  }
                }
              },
            ),
            
            const SizedBox(height: 16),
            Divider(color: AppColors.muted),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Date Personale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
                if (_isPrivate) 
                  TextButton.icon(
                    onPressed: _showFollowRequestsDialog,
                    icon: Icon(Icons.group_add, color: AppColors.accent, size: 18),
                    label: Text('Cereri', style: TextStyle(color: AppColors.accent)),
                  ),
              ],
            ),
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
                side: BorderSide(color: AppColors.muted),
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
            child: Text(value, style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }

  Widget _buildProfileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
