import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/level_utils.dart';
import 'chat_screen.dart';
import '../widgets/player_drawer.dart';

class MyMatchesScreen extends StatefulWidget {
  const MyMatchesScreen({super.key});

  @override
  State<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

class _MyMatchesScreenState extends State<MyMatchesScreen> {
  Future<void> _sendFriendRequestFromTable(Map<String, dynamic> player) async {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) return;

    final targetUid = player['uid'];
    final targetUsername = player['username'] ?? 'Utilizator';
    final targetAvatarUrl = player['avatarUrl'] ?? '';

    try {
      // 1. Verificare anti-spam: sunt deja prieteni?
      final String friendshipId = currentUserUid.compareTo(targetUid) < 0
          ? '${currentUserUid}_$targetUid'
          : '${targetUid}_$currentUserUid';

      final friendshipDoc = await FirebaseFirestore.instance.collection('friendships').doc(friendshipId).get();
      if (friendshipDoc.exists) {
        _showDialogMessage('Sunteți deja prieteni!', 'Acest utilizator face deja parte din lista ta de prieteni.');
        return;
      }

      // 2. Verificare anti-spam: există deja o cerere pending de la mine la ei?
      final sentRequestQuery = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: currentUserUid)
          .where('toUid', isEqualTo: targetUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (sentRequestQuery.docs.isNotEmpty) {
        _showDialogMessage('Cerere deja trimisă!', 'Ai trimis deja o cerere de prietenie către acest utilizator. Cererea este în așteptare.');
        return;
      }

      // 3. Verificare anti-spam: există deja o cerere pending de la ei la mine?
      final receivedRequestQuery = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: currentUserUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (receivedRequestQuery.docs.isNotEmpty) {
        _showDialogMessage('Cerere în așteptare!', 'Acest utilizator ți-a trimis deja o cerere de prietenie! O poți accepta din ecranul Prieteni.');
        return;
      }

      // Get my details for the request
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserUid).get();
      final myData = myDoc.data() ?? {};
      final myUsername = myData['username'] ?? 'Utilizator';
      final myAvatarUrl = myData['avatarUrl'] ?? '';

      // Save friend request doc
      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUid': currentUserUid,
        'fromUsername': myUsername,
        'fromAvatarUrl': myAvatarUrl,
        'toUid': targetUid,
        'toUsername': targetUsername,
        'toAvatarUrl': targetAvatarUrl,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cerere de prietenie trimisă către $targetUsername!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showDialogMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );
  }

  bool _isPast(Map<String, dynamic> data) {
    try {
      final dateStr = data['date'] as String;
      final endHour = data['endHour'] as int;
      final matchEnd = DateTime.parse('$dateStr ${endHour.toString().padLeft(2, '0')}:00:00');
      return DateTime.now().isAfter(matchEnd);
    } catch (e) {
      return false;
    }
  }

  void _showReportDialog(String matchId, Map<String, dynamic> matchData) {
    showDialog(
      context: context,
      builder: (context) {
        return _ReportResultDialog(
          matchId: matchId,
          matchData: matchData,
        );
      },
    );
  }

  Widget _buildReportSummary(Map<String, dynamic> data) {
    final reportType = data['reportType'] ?? '1v1';
    if (reportType == '1v1') {
      final myWins = data['myWins'] ?? 0;
      final myLosses = data['myLosses'] ?? 0;
      return Text(
        'Scor raportat de adversar: $myWins - $myLosses (${myWins > myLosses ? 'A câștigat' : 'A pierdut'})',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      );
    } else {
      final List<dynamic> reportedMatches = data['reportedMatches'] ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total meciuri jucate: ${data['totalMatches'] ?? 0}',
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...reportedMatches.map((m) {
            final partner = m['partnerUsername'] ?? 'Partener';
            final outcome = m['outcome'] == 'win' ? '🏆 Câștigat' : '❌ Pierdut';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• În echipă cu $partner: $outcome',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            );
          }).toList(),
        ],
      );
    }
  }

  Future<void> _disputeReport(String matchId) async {
    try {
      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
        'status': 'matched',
        'reporterUid': FieldValue.delete(),
        'reporterUsername': FieldValue.delete(),
        'reportType': FieldValue.delete(),
        'totalMatches': FieldValue.delete(),
        'myWins': FieldValue.delete(),
        'myLosses': FieldValue.delete(),
        'reportedMatches': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezultatul a fost contestat. Puteți raporta din nou!'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _confirmReport(String matchId, Map<String, dynamic> matchData) async {
    try {
      final List<dynamic> joinedUids = matchData['joinedUids'] ?? [];
      final reportType = matchData['reportType'] ?? '1v1';
      final reporterUid = matchData['reporterUid'] ?? '';
      final bool isFriendly = matchData['isFriendly'] == true;

      if (joinedUids.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();

      if (!isFriendly) {
        if (reportType == '1v1') {
          final myWins = matchData['myWins'] ?? 0;
          final myLosses = matchData['myLosses'] ?? 0;
          
          final opponentUid = joinedUids.firstWhere((uid) => uid != reporterUid, orElse: () => '');

          if (opponentUid.isNotEmpty && reporterUid.isNotEmpty) {
            String winnerUid = myWins > myLosses ? reporterUid : opponentUid;
            String loserUid = myWins > myLosses ? opponentUid : reporterUid;

            // Fetch ratings
            final winnerDoc = await FirebaseFirestore.instance.collection('users').doc(winnerUid).get();
            final loserDoc = await FirebaseFirestore.instance.collection('users').doc(loserUid).get();

            int winnerRating = winnerDoc.data()?['rating'] ?? 0;
            int loserRating = loserDoc.data()?['rating'] ?? 0;

            int winPoints = LevelUtils.calculateMatchPoints(winnerRating, loserRating);
            int losePoints = LevelUtils.getLevelDetails(loserRating)['losePoints'] as int;

            batch.update(FirebaseFirestore.instance.collection('users').doc(winnerUid), {
              'rating': winnerRating + winPoints,
            });

            batch.update(FirebaseFirestore.instance.collection('users').doc(loserUid), {
              'rating': (loserRating - losePoints < 0) ? 0 : loserRating - losePoints,
            });
          }
        } else {
          // 2v2 multiple matches reporting
          final List<dynamic> reportedMatches = matchData['reportedMatches'] ?? [];
          Map<String, int> winsCount = {};
          Map<String, int> lossesCount = {};

          for (var uid in joinedUids) {
            winsCount[uid.toString()] = 0;
            lossesCount[uid.toString()] = 0;
          }

          for (var m in reportedMatches) {
            final partnerUid = m['partnerUid']?.toString() ?? '';
            final outcome = m['outcome']?.toString() ?? 'win';

            // Opponents are all other UIDs that are not reporter and not partner
            final opponents = joinedUids.where((uid) => uid.toString() != reporterUid && uid.toString() != partnerUid).toList();

            if (outcome == 'win') {
              winsCount[reporterUid] = (winsCount[reporterUid] ?? 0) + 1;
              if (partnerUid.isNotEmpty) {
                winsCount[partnerUid] = (winsCount[partnerUid] ?? 0) + 1;
              }
              for (var opp in opponents) {
                final oppStr = opp.toString();
                lossesCount[oppStr] = (lossesCount[oppStr] ?? 0) + 1;
              }
            } else {
              lossesCount[reporterUid] = (lossesCount[reporterUid] ?? 0) + 1;
              if (partnerUid.isNotEmpty) {
                lossesCount[partnerUid] = (lossesCount[partnerUid] ?? 0) + 1;
              }
              for (var opp in opponents) {
                final oppStr = opp.toString();
                winsCount[oppStr] = (winsCount[oppStr] ?? 0) + 1;
              }
            }
          }

          // Apply rating updates for all 4 players
          for (var uid in joinedUids) {
            final uidStr = uid.toString();
            final wins = winsCount[uidStr] ?? 0;
            final losses = lossesCount[uidStr] ?? 0;

            if (wins > losses) {
              // Player won more than they lost overall
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uidStr).get();
              final rating = userDoc.data()?['rating'] ?? 0;
              final winPoints = LevelUtils.getLevelDetails(rating)['winPoints'] as int;
              batch.update(FirebaseFirestore.instance.collection('users').doc(uidStr), {
                'rating': rating + winPoints,
              });
            } else if (wins < losses) {
              // Player lost more than they won overall
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uidStr).get();
              final rating = userDoc.data()?['rating'] ?? 0;
              final losePoints = LevelUtils.getLevelDetails(rating)['losePoints'] as int;
              batch.update(FirebaseFirestore.instance.collection('users').doc(uidStr), {
                'rating': (rating - losePoints < 0) ? 0 : rating - losePoints,
              });
            }
          }
        }
      }

      batch.update(FirebaseFirestore.instance.collection('matches').doc(matchId), {
        'status': 'completed',
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFriendly 
                ? 'Rezultat confirmat! Meciul fiind Amical, punctele nu au fost modificate.'
                : 'Rezultat confirmat! Punctele au fost actualizate.'
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _cancelMatch(String matchId) async {
    try {
      await FirebaseFirestore.instance.collection('matches').doc(matchId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat cu succes!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare la anulare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _withdraw(String matchId, Map<String, dynamic> data, bool isHost) async {
    final userUid = FirebaseAuth.instance.currentUser!.uid;
    List<dynamic> joinedPlayers = List.from(data['joinedPlayers'] ?? []);
    List<dynamic> joinedUids = List.from(data['joinedUids'] ?? []);

    joinedPlayers.removeWhere((p) => p['uid'] == userUid);
    joinedUids.remove(userUid);

    Map<String, dynamic> updates = {
      'joinedPlayers': joinedPlayers,
      'joinedUids': joinedUids,
      'status': 'open',
    };

    if (isHost) {
      if (joinedPlayers.isNotEmpty) {
        // Promote first guest to host
        final newHost = joinedPlayers.first;
        updates['hostUid'] = newHost['uid'];
        updates['hostUsername'] = newHost['username'];
        updates['hostAvatarUrl'] = newHost['avatarUrl'];
        updates['hostRating'] = newHost['rating'];
        updates['hostLevel'] = newHost['level'];
        
        int newHostIndex = joinedPlayers.indexWhere((p) => p['uid'] == newHost['uid']);
        if (newHostIndex != -1) {
           joinedPlayers[newHostIndex]['role'] = 'host';
           updates['joinedPlayers'] = joinedPlayers;
        }
      } else {
        // Everyone left, delete match
        await _cancelMatch(matchId);
        return;
      }
    }

    try {
      await FirebaseFirestore.instance.collection('matches').doc(matchId).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Te-ai retras de la masă.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildMatchCard(String docId, Map<String, dynamic> data, bool isPast) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final isHost = data['hostUid'] == currentUserUid;
    final isCompleted = data['status'] == 'completed';
    final List<dynamic> players = data['joinedPlayers'] ?? [];
    
    bool canCancel = false;
    try {
      final dateStr = data['date'] as String;
      final startHour = data['startHour'] as int;
      final matchStart = DateTime.parse('$dateStr ${startHour.toString().padLeft(2, '0')}:00:00');
      if (matchStart.difference(DateTime.now()).inHours >= 24) {
        canCancel = true;
      }
    } catch (_) {}

    return Card(
      color: const Color(0xFF131A2A),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('${data['locationName']} (${data['city']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                  child: Text(data['visibility'] == 'private' ? 'Privat' : 'Public', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 8),
            Text('${data['date']} | ${data['startHour']}:00 - ${data['endHour']}:00', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            const Text('Jucători la masă:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            ...players.map((p) {
              final isMe = p['uid'] == currentUserUid;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      p['role'] == 'host' ? Icons.star : Icons.person, 
                      size: 16, 
                      color: p['role'] == 'host' ? Colors.yellow : Colors.grey
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p['username']} (${p['level']})', 
                        style: TextStyle(
                          color: isMe ? const Color(0xFF00E5FF) : Colors.white,
                          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ),
                    if (!isMe) ...[
                      // Chat button
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 18),
                        tooltip: 'Trimite mesaj',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otherUid: p['uid'],
                                otherUsername: p['username'] ?? 'Utilizator',
                                otherAvatarUrl: p['avatarUrl'],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Friend request button
                      IconButton(
                        icon: const Icon(Icons.person_add_outlined, color: Colors.greenAccent, size: 18),
                        tooltip: 'Adaugă prieten',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        onPressed: () => _sendFriendRequestFromTable(p),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
            if (players.length < (data['maxPlayers'] ?? 2))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Mai sunt ${(data['maxPlayers'] ?? 2) - players.length} locuri libere...', style: const TextStyle(color: Colors.yellowAccent, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            if (isCompleted)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('Meci finalizat și puncte acordate!', style: TextStyle(color: Colors.green)),
              )
            else if (isPast && (data['status'] == 'matched' || data['status'] == 'reported')) ...[
              if (data['status'] == 'reported') ...[
                if (data['reporterUid'] == currentUserUid)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_empty, color: Color(0xFF00E5FF), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Scorul a fost raportat. Așteptăm confirmarea celorlalți jucători.',
                            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data['reporterUsername'] ?? 'Un jucător'} a raportat rezultatul:',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            _buildReportSummary(data),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _confirmReport(docId, data),
                              child: const Text('Confirmă Rezultatul'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              onPressed: () => _disputeReport(docId),
                              child: const Text('Contestă'),
                            ),
                          ),
                        ],
                      )
                    ],
                  )
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.analytics_outlined),
                        label: const Text('RAPORTEAZĂ REZULTAT', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _showReportDialog(docId, data),
                      ),
                    ),
                  ],
                )
              ]
            ] else if (!isPast) ...[
              Row(
                children: [
                  if (isHost && canCancel)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                        onPressed: () => _cancelMatch(docId),
                        child: const Text('Anulează Masa'),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                        onPressed: () => _withdraw(docId, data, isHost),
                        child: const Text('Retrage-te (Leave)'),
                      ),
                    ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserUid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meciurile Mele')),
        body: const Center(child: Text('Trebuie să fii autentificat!')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          title: const Text('Meciurile Mele'),
          bottom: const TabBar(
            indicatorColor: Color(0xFF00E5FF),
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past (De raportat)'),
            ],
          ),
        ),
        drawer: const PlayerDrawer(activePage: 'my_matches'),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('matches')
              .where('joinedUids', arrayContains: currentUserUid)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Eroare la încărcare.', style: TextStyle(color: Colors.red)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
            }

            final docs = snapshot.data!.docs;
            final upcoming = <QueryDocumentSnapshot>[];
            final past = <QueryDocumentSnapshot>[];

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (_isPast(data)) {
                past.add(doc);
              } else {
                upcoming.add(doc);
              }
            }

            return TabBarView(
              children: [
                upcoming.isEmpty
                    ? const Center(child: Text('Niciun meci viitor.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: upcoming.length,
                        itemBuilder: (context, index) => _buildMatchCard(upcoming[index].id, upcoming[index].data() as Map<String, dynamic>, false),
                      ),
                past.isEmpty
                    ? const Center(child: Text('Niciun meci trecut.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: past.length,
                        itemBuilder: (context, index) => _buildMatchCard(past[index].id, past[index].data() as Map<String, dynamic>, true),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReportResultDialog extends StatefulWidget {
  final String matchId;
  final Map<String, dynamic> matchData;

  const _ReportResultDialog({
    required this.matchId,
    required this.matchData,
  });

  @override
  State<_ReportResultDialog> createState() => _ReportResultDialogState();
}

class _ReportResultDialogState extends State<_ReportResultDialog> {
  int _totalMatches = 5;
  
  // 1v1 specific state
  int _myWins = 3;

  // 2v2 specific state
  List<Map<String, dynamic>> _matches2v2 = [];

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final List<dynamic> joinedUids = widget.matchData['joinedUids'] ?? [];
    final bool is2v2 = joinedUids.length >= 4;
    if (is2v2) {
      _init2v2Matches();
    }
  }

  void _init2v2Matches() {
    _matches2v2 = List.generate(_totalMatches, (index) {
      final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
      final List<dynamic> players = widget.matchData['joinedPlayers'] ?? [];
      final otherPlayers = players.where((p) => p['uid'] != currentUserUid).toList();
      final defaultPartner = otherPlayers.isNotEmpty ? otherPlayers.first : null;

      return {
        'partnerUid': defaultPartner?['uid'] ?? '',
        'partnerUsername': defaultPartner?['username'] ?? 'Jucător',
        'outcome': 'win',
      };
    });
  }

  void _updateTotalMatches(int newTotal) {
    setState(() {
      _totalMatches = newTotal;
      if (_myWins > _totalMatches) {
        _myWins = _totalMatches;
      }
      final List<dynamic> joinedUids = widget.matchData['joinedUids'] ?? [];
      if (joinedUids.length >= 4) {
        _init2v2Matches();
      }
    });
  }

  Future<void> _submitReport() async {
    setState(() => _isSubmitting = true);
    try {
      final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
      
      // Get reporter username
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserUid).get();
      final reporterUsername = userDoc.data()?['username'] ?? 'Jucător';

      final List<dynamic> joinedUids = widget.matchData['joinedUids'] ?? [];
      final bool is2v2 = joinedUids.length >= 4;

      final reportUpdates = {
        'status': 'reported',
        'reporterUid': currentUserUid,
        'reporterUsername': reporterUsername,
        'reportType': is2v2 ? '2v2' : '1v1',
        'totalMatches': _totalMatches,
      };

      if (!is2v2) {
        reportUpdates['myWins'] = _myWins;
        reportUpdates['myLosses'] = _totalMatches - _myWins;
        reportUpdates['score'] = '$_myWins-${_totalMatches - _myWins}';
      } else {
        reportUpdates['reportedMatches'] = _matches2v2;
      }

      await FirebaseFirestore.instance.collection('matches').doc(widget.matchId).update(reportUpdates);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezultatul a fost raportat cu succes!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la raportare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> joinedUids = widget.matchData['joinedUids'] ?? [];
    final bool is2v2 = joinedUids.length >= 4;
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final List<dynamic> players = widget.matchData['joinedPlayers'] ?? [];
    final otherPlayers = players.where((p) => p['uid'] != currentUserUid).toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF131A2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
      ),
      title: Text(
        is2v2 ? 'Raportare Meci 2v2' : 'Raportare Meci 1v1',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Câte meciuri ați jucat în total?',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _totalMatches.toDouble(),
                      min: 1,
                      max: 15,
                      divisions: 14,
                      activeColor: const Color(0xFF00E5FF),
                      inactiveColor: const Color(0xFF1E293B),
                      label: _totalMatches.toString(),
                      onChanged: (val) => _updateTotalMatches(val.round()),
                    ),
                  ),
                  Text(
                    _totalMatches.toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!is2v2) ...[
                Text(
                  'Meciuri câștigate de tine: $_myWins',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _myWins.toDouble(),
                        min: 0,
                        max: _totalMatches.toDouble(),
                        divisions: _totalMatches,
                        activeColor: Colors.greenAccent,
                        inactiveColor: const Color(0xFF1E293B),
                        label: _myWins.toString(),
                        onChanged: (val) => setState(() => _myWins = val.round()),
                      ),
                    ),
                    Text(
                      '${_totalMatches - _myWins} pierdute',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Scor raportat: $_myWins - ${_totalMatches - _myWins}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF), fontSize: 16),
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  'Detalii pentru fiecare meci:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                ...List.generate(_totalMatches, (index) {
                  if (index >= _matches2v2.length) return const SizedBox();
                  final match = _matches2v2[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Meciul ${index + 1}',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        const Text('Partenerul tău:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        DropdownButton<String>(
                          value: match['partnerUid'],
                          isExpanded: true,
                          dropdownColor: const Color(0xFF131A2A),
                          style: const TextStyle(color: Colors.white),
                          items: otherPlayers.map((p) {
                            return DropdownMenuItem<String>(
                              value: p['uid'],
                              child: Text(p['username'] ?? 'Jucător'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              final selectedPlayer = otherPlayers.firstWhere((p) => p['uid'] == val);
                              setState(() {
                                _matches2v2[index]['partnerUid'] = val;
                                _matches2v2[index]['partnerUsername'] = selectedPlayer['username'] ?? 'Jucător';
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Rezultat:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() => _matches2v2[index]['outcome'] = 'win'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: match['outcome'] == 'win' ? Colors.green : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Text('Câștigat', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(() => _matches2v2[index]['outcome'] = 'lose'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: match['outcome'] == 'lose' ? Colors.red : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.red),
                                    ),
                                    child: const Text('Pierdut', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('RENUNȚĂ', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: _isSubmitting ? null : _submitReport,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('SALVEAZĂ', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
