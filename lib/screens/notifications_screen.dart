import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/level_utils.dart';

class NotificationsDialog extends StatefulWidget {
  const NotificationsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const NotificationsDialog(),
    );
  }

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  Future<void> _handleInviteDecision(String notificationId, String matchId, bool accept) async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final matchDoc = await FirebaseFirestore.instance.collection('matches').doc(matchId).get();
      if (!matchDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Acest meci nu mai există.'), backgroundColor: Colors.redAccent),
          );
        }
        // Mark notification as resolved since match is gone
        await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({'status': 'invalid'});
        return;
      }

      final matchData = matchDoc.data()!;
      List<dynamic> joinedPlayers = List.from(matchData['joinedPlayers'] ?? []);
      List<dynamic> joinedUids = List.from(matchData['joinedUids'] ?? []);
      int maxPlayers = matchData['maxPlayers'] ?? 2;

      if (accept) {
        if (joinedUids.contains(user.uid)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ești deja înscris la acest meci!'), backgroundColor: Colors.orangeAccent),
            );
          }
          await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({'status': 'accepted'});
          return;
        }

        if (joinedPlayers.length >= maxPlayers) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Masa este deja plină.'), backgroundColor: Colors.redAccent),
            );
          }
          await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({'status': 'full'});
          return;
        }

        // Get user details
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userData = userDoc.data() ?? {};
        final username = userData['username'] ?? 'Jucător';
        final avatarUrl = userData['avatarUrl'];
        final rating = userData['rating'] ?? 0;
        final levelName = LevelUtils.getLevelDetails(rating)['levelName'];

        final newPlayer = {
          'uid': user.uid,
          'username': username,
          'avatarUrl': avatarUrl,
          'rating': rating,
          'level': levelName,
          'role': 'guest'
        };

        joinedPlayers.add(newPlayer);
        joinedUids.add(user.uid);

        String newStatus = (joinedPlayers.length >= maxPlayers) ? 'matched' : 'open';

        // Update match and notification in a batch
        final batch = FirebaseFirestore.instance.batch();
        batch.update(FirebaseFirestore.instance.collection('matches').doc(matchId), {
          'status': newStatus,
          'joinedPlayers': joinedPlayers,
          'joinedUids': joinedUids,
        });

        batch.update(FirebaseFirestore.instance.collection('notifications').doc(notificationId), {
          'status': 'accepted',
        });

        // Send a notification back to the host that the user accepted the invite
        final hostUid = matchData['hostUid'];
        if (hostUid != null && hostUid != user.uid) {
          final replyNotificationRef = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(replyNotificationRef, {
            'toUid': hostUid,
            'fromUid': user.uid,
            'fromUsername': username,
            'fromAvatarUrl': avatarUrl,
            'title': 'Invitație acceptată',
            'body': '$username a acceptat invitația la meciul din ${matchData['date']}.',
            'type': 'match_accept',
            'status': 'pending',
            'matchId': matchId,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ai acceptat invitația! Meciul a fost adăugat în program.'), backgroundColor: Colors.green),
          );
        }
      } else {
        // Decline invite
        await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({
          'status': 'declined',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitație refuzată.'), backgroundColor: Colors.grey),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _dismissNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(notificationId).update({
        'status': 'read',
      });
    } catch (e) {
      debugPrint('Eroare la ștergerea notificării: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    if (user == null) {
      return Dialog(
        backgroundColor: const Color(0xFF0A0E17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('Trebuie să fii autentificat!', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: Color(0xFF00E5FF), size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Notificări Meciuri',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),
            // Body
            Flexible(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('toUid', isEqualTo: user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Eroare la încărcare: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  
                  // Sort client-side by timestamp descending to avoid composite index requirement
                  final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
                  sortedDocs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final Timestamp? aTime = aData['timestamp'];
                    final Timestamp? bTime = bData['timestamp'];
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  // Filter out friend requests client-side
                  final filteredDocs = sortedDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] ?? '';
                    final status = data['status'] ?? 'pending';
                    return type != 'friend_request' && status == 'pending';
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Nicio notificare nouă.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          SizedBox(height: 8),
                          Text(
                            'Aici vei primi invitații de meci, confirmări și alerte de la masa ta.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final docId = filteredDocs[index].id;
                      final data = filteredDocs[index].data() as Map<String, dynamic>;
                      final title = data['title'] ?? 'Notificare';
                      final body = data['body'] ?? '';
                      final type = data['type'] ?? '';
                      final matchId = data['matchId'] ?? '';
                      final Timestamp? timestamp = data['timestamp'];

                      final timeStr = timestamp != null
                          ? DateFormat('dd MMM, HH:mm').format(timestamp.toDate())
                          : '';

                      final bool isInvite = type == 'match_invite';

                      return Card(
                        color: const Color(0xFF131A2A),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          isInvite ? Icons.sports_tennis : Icons.info_outline,
                                          color: const Color(0xFF00E5FF),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 12),
                              if (isInvite) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00E5FF),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () => _handleInviteDecision(docId, matchId, true),
                                        child: const Text('ACCEPTĂ'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.redAccent),
                                          foregroundColor: Colors.redAccent,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () => _handleInviteDecision(docId, matchId, false),
                                        child: const Text('REFUZĂ'),
                                      ),
                                    ),
                                  ],
                                )
                              ] else ...[
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _dismissNotification(docId),
                                    child: const Text(
                                      'CONFIRMĂ',
                                      style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                )
                              ]
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
