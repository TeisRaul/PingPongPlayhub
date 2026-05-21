import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/level_utils.dart';
import 'chat_screen.dart';

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

  Future<void> _reportResult(String matchId, Map<String, dynamic> matchData, bool iWon) async {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    final isHost = matchData['hostUid'] == currentUserUid;
    final myRole = isHost ? 'hostReport' : 'guestReport';

    await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
      myRole: iWon ? 'win' : 'lose',
    });

    final doc = await FirebaseFirestore.instance.collection('matches').doc(matchId).get();
    final data = doc.data()!;
    final hostReport = data['hostReport'];
    final guestReport = data['guestReport'];

    if (hostReport != null && guestReport != null && data['status'] != 'completed') {
      if ((hostReport == 'win' && guestReport == 'lose') || (hostReport == 'lose' && guestReport == 'win')) {
        String winnerUid = hostReport == 'win' ? data['hostUid'] : (data['joinedUids'].length > 1 ? data['joinedUids'][1] : '');
        String loserUid = hostReport == 'lose' ? data['hostUid'] : (data['joinedUids'].length > 1 ? data['joinedUids'][1] : '');
        
        int winnerRating = hostReport == 'win' ? (data['hostRating'] ?? 0) : 0;
        int loserRating = hostReport == 'lose' ? (data['hostRating'] ?? 0) : 0;

        int winPoints = LevelUtils.calculateMatchPoints(winnerRating, loserRating);
        int losePoints = LevelUtils.getLevelDetails(winnerRating)['losePoints'] as int;
        
        if (winnerUid.isNotEmpty) {
          final winnerDoc = await FirebaseFirestore.instance.collection('users').doc(winnerUid).get();
          int wRating = winnerDoc.data()?['rating'] ?? 0;
          await FirebaseFirestore.instance.collection('users').doc(winnerUid).update({'rating': wRating + winPoints});
        }
        
        if (loserUid.isNotEmpty) {
          final loserDoc = await FirebaseFirestore.instance.collection('users').doc(loserUid).get();
          int lRating = loserDoc.data()?['rating'] ?? 0;
          await FirebaseFirestore.instance.collection('users').doc(loserUid).update({'rating': (lRating - losePoints < 0) ? 0 : lRating - losePoints});
        }

        await FirebaseFirestore.instance.collection('matches').doc(matchId).update({'status': 'completed'});
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rezultat confirmat!'), backgroundColor: Colors.green));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rezultate conflictuale.'), backgroundColor: Colors.red));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Așteptăm confirmarea celuilalt jucător.'), backgroundColor: Color(0xFF00E5FF)));
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
            else if (isPast && data['status'] == 'matched') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => _reportResult(docId, data, true),
                      child: const Text('Am Câștigat'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => _reportResult(docId, data, false),
                      child: const Text('Am Pierdut'),
                    ),
                  ),
                ],
              )
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
          title: const Text('Meciurile Mele'),
          bottom: const TabBar(
            indicatorColor: Color(0xFF00E5FF),
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past (De raportat)'),
            ],
          ),
        ),
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
