import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/level_utils.dart';
import '../widgets/player_drawer.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedFilter = 'Global'; // 'Global' sau 'Orașul Meu' (sau un oraș anume)

  Widget _buildTop3Card(Map<String, dynamic> data, int rank) {
    Color rankColor;
    double avatarRadius;
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700); // Gold
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
                backgroundColor: const Color(0xFF1E293B),
                backgroundImage: data['avatarUrl'] != null && data['avatarUrl'].toString().isNotEmpty
                    ? NetworkImage(data['avatarUrl'])
                    : null,
                child: data['avatarUrl'] == null || data['avatarUrl'].toString().isEmpty
                    ? Text((data['username'] ?? 'J').toString()[0].toUpperCase(),
                        style: TextStyle(color: Colors.white, fontSize: avatarRadius, fontWeight: FontWeight.bold))
                    : null,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0A0E17), width: 2),
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
          data['username'] ?? 'Jucător',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          levelName,
          style: TextStyle(color: rankColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        Text(
          '$rating PTS',
          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Jucători (Live)'),
        centerTitle: true,
        backgroundColor: const Color(0xFF131A2A),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Color(0xFF00E5FF)),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'Global',
                child: Text('Global (Toată Țara)'),
              ),
              // We could add dynamic cities here if we have a user city
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const PlayerDrawer(activePage: 'leaderboard'),
      body: Container(
        color: const Color(0xFF0A0E17),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              // Vom asuma ca toti jucatorii au rating
              .orderBy('rating', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text('Nu există jucători în clasament momentan.', style: TextStyle(color: Colors.white)),
              );
            }

            final players = snapshot.data!.docs.map((d) => d.data() as Map<String, dynamic>).toList();

            return CustomScrollView(
              slivers: [
                if (players.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.only(top: 30, bottom: 20, left: 16, right: 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF131A2A), Color(0xFF0A0E17)],
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
                          color: const Color(0xFF131A2A),
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
                                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF1E293B),
                                backgroundImage: data['avatarUrl'] != null && data['avatarUrl'].toString().isNotEmpty
                                    ? NetworkImage(data['avatarUrl'])
                                    : null,
                                child: data['avatarUrl'] == null || data['avatarUrl'].toString().isEmpty
                                    ? Text((data['username'] ?? 'J').toString()[0].toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ],
                          ),
                          title: Text(
                            data['username'] ?? 'Jucător',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            levelName,
                            style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$rating PTS',
                              style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
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
