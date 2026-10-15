import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/level_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/strings.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedFilter = 'global'; // 'global' sau 'city' (orașul contului curent)
  String _myCity = '';

  @override
  void initState() {
    super.initState();
    _loadMyCity();
  }

  Future<void> _loadMyCity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final city = (doc.data()?['city'] ?? '').toString();
      if (mounted) setState(() => _myCity = city);
    } catch (_) {}
  }

  /// Conturile de test (seed) nu apar în clasament: au id `fake_*`, flag `isSeed`
  /// sau nu au deloc câmpurile completate la înregistrare (uid / prenume / dată naștere).
  bool _isRealPlayer(String docId, Map<String, dynamic> data) {
    if (docId.startsWith('fake_') || data['isSeed'] == true) return false;
    if ((data['username'] ?? '').toString().trim().isEmpty) return false;
    return data['uid'] != null || data['firstName'] != null || data['dob'] != null;
  }

  Widget _buildTop3Card(Map<String, dynamic> data, int rank) {
    Color rankColor;
    double avatarRadius;
    if (rank == 1) {
      rankColor = AppColors.gold; // Gold
      avatarRadius = 35;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0); // Silver
      avatarRadius = 28;
    } else {
      rankColor = const Color(0xFFCD7F32); // Bronze
      avatarRadius = 25;
    }

    final rating = data['rating'] ?? 0;
    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 15),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: rankColor, width: 3),
              ),
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: AppColors.card2,
                backgroundImage: data['avatarUrl'] != null && data['avatarUrl'].toString().isNotEmpty
                    ? NetworkImage(data['avatarUrl'])
                    : null,
                child: data['avatarUrl'] == null || data['avatarUrl'].toString().isEmpty
                    ? Text((data['username'] ?? 'J').toString()[0].toUpperCase(),
                        style: TextStyle(color: AppColors.text, fontSize: avatarRadius, fontWeight: FontWeight.bold))
                    : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          data['username'] ?? tr('lb.player'),
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          levelName,
          style: TextStyle(color: rankColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        Text(
          tr('lb.pts', {'points': '$rating'}),
          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('lb.title')),
        centerTitle: true,
        backgroundColor: AppColors.card,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: AppColors.accent),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'global',
                child: Text(tr('lb.global')),
              ),
              if (_myCity.isNotEmpty)
                PopupMenuItem(
                  value: 'city',
                  child: Text(tr('lb.my_city', {'city': _myCity})),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const PlayerDrawer(activePage: 'leaderboard'),
      body: Container(
        color: AppColors.bg,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              // Vom asuma ca toti jucatorii au rating
              .orderBy('rating', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: AppColors.accent));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Text(tr('lb.empty'), style: TextStyle(color: AppColors.text)),
              );
            }

            final players = snapshot.data!.docs
                .where((d) => _isRealPlayer(d.id, d.data() as Map<String, dynamic>))
                .map((d) => d.data() as Map<String, dynamic>)
                .where((p) => _selectedFilter != 'city' || (p['city'] ?? '').toString() == _myCity)
                .toList();

            if (players.isEmpty) {
              return Center(
                child: Text(tr('lb.empty'), style: TextStyle(color: AppColors.text)),
              );
            }

            return CustomScrollView(
              slivers: [
                if (players.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.only(top: 30, bottom: 20, left: 16, right: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.card, AppColors.bg],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (players.length > 1) Expanded(child: _buildTop3Card(players[1], 2)),
                          if (players.isNotEmpty) Expanded(child: Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: _buildTop3Card(players[0], 1),
                          )),
                          if (players.length > 2) Expanded(child: _buildTop3Card(players[2], 3)),
                        ],
                      ),
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // skip first 3
                      if (index < 3) return const SizedBox.shrink();
                      
                      final data = players[index];
                      final rating = data['rating'] ?? 0;
                      final levelDetails = LevelUtils.getLevelDetails(rating);
                      final String levelName = levelDetails['levelName'];
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.card2,
                                backgroundImage: data['avatarUrl'] != null && data['avatarUrl'].toString().isNotEmpty
                                    ? NetworkImage(data['avatarUrl'])
                                    : null,
                                child: data['avatarUrl'] == null || data['avatarUrl'].toString().isEmpty
                                    ? Text((data['username'] ?? 'J').toString()[0].toUpperCase(),
                                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ],
                          ),
                          title: Text(
                            data['username'] ?? tr('lb.player'),
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            levelName,
                            style: TextStyle(color: AppColors.accent, fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tr('lb.pts', {'points': '$rating'}),
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: players.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          },
        ),
      ),
    );
  }
}
