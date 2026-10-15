import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'match_detail_screen.dart';
import '../services/notification_service.dart';
import '../services/trainer_service.dart';
import '../utils/hour_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/booking_service.dart';
import '../services/checkin_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/level_utils.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'chat_screen.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

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
        backgroundColor: AppColors.card,
        title: Text(title, style: TextStyle(color: AppColors.text)),
        content: Text(message, style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  bool _isPast(Map<String, dynamic> data) {
    try {
      final dateStr = data['date'] as String;
      final endHour = hourValue(data['endHour']);
      final matchEnd = dateAtHour(dateStr, endHour);
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
        style: TextStyle(color: AppColors.text70, fontSize: 13),
      );
    } else {
      final List<dynamic> reportedMatches = data['reportedMatches'] ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total meciuri jucate: ${data['totalMatches'] ?? 0}',
            style: TextStyle(color: AppColors.text70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...reportedMatches.map((m) {
            final partner = m['partnerUsername'] ?? 'Partener';
            final outcome = m['outcome'] == 'win' ? '🏆 Câștigat' : '❌ Pierdut';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• În echipă cu $partner: $outcome',
                style: TextStyle(color: AppColors.text70, fontSize: 13),
              ),
            );
          }),
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

      // Câștigătorul se salvează și la meciurile amicale (doar punctele nu se modifică).
      String? matchWinnerUid;
      final List<String> matchWinnerUids = [];
      // Rating înainte / după pentru fiecare jucător (alimentează evoluția din Statistici).
      final Map<String, dynamic> ratingChanges = {};

      {
        if (reportType == '1v1') {
          final myWins = matchData['myWins'] ?? 0;
          final myLosses = matchData['myLosses'] ?? 0;
          
          final opponentUid = joinedUids.firstWhere((uid) => uid != reporterUid, orElse: () => '');

          // La egalitate nu există câștigător și punctele rămân neschimbate.
          if (opponentUid.isNotEmpty && reporterUid.isNotEmpty && myWins != myLosses) {
            String winnerUid = myWins > myLosses ? reporterUid : opponentUid;
            String loserUid = myWins > myLosses ? opponentUid : reporterUid;
            matchWinnerUid = winnerUid;

            if (!isFriendly) {
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
            ratingChanges[winnerUid] = {'before': winnerRating, 'after': winnerRating + winPoints};

            batch.update(FirebaseFirestore.instance.collection('users').doc(loserUid), {
              'rating': (loserRating - losePoints < 0) ? 0 : loserRating - losePoints,
            });
            ratingChanges[loserUid] = {
              'before': loserRating,
              'after': (loserRating - losePoints < 0) ? 0 : loserRating - losePoints,
            };
            }
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

            if (wins > losses) matchWinnerUids.add(uidStr);
            if (isFriendly) continue;

            if (wins > losses) {
              // Player won more than they lost overall
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uidStr).get();
              final rating = userDoc.data()?['rating'] ?? 0;
              final winPoints = LevelUtils.getLevelDetails(rating)['winPoints'] as int;
              batch.update(FirebaseFirestore.instance.collection('users').doc(uidStr), {
                'rating': rating + winPoints,
              });
              ratingChanges[uidStr] = {'before': rating, 'after': rating + winPoints};
            } else if (wins < losses) {
              // Player lost more than they won overall
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uidStr).get();
              final rating = userDoc.data()?['rating'] ?? 0;
              final losePoints = LevelUtils.getLevelDetails(rating)['losePoints'] as int;
              batch.update(FirebaseFirestore.instance.collection('users').doc(uidStr), {
                'rating': (rating - losePoints < 0) ? 0 : rating - losePoints,
              });
              ratingChanges[uidStr] = {
                'before': rating,
                'after': (rating - losePoints < 0) ? 0 : rating - losePoints,
              };
            }
          }
        }
      }

      batch.update(FirebaseFirestore.instance.collection('matches').doc(matchId), {
        'status': 'completed',
        if (matchWinnerUid != null) 'winnerUid': matchWinnerUid,
        if (matchWinnerUids.isNotEmpty) 'winnerUids': matchWinnerUids,
        if (ratingChanges.isNotEmpty) 'ratingChanges': ratingChanges,
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
      final ref = FirebaseFirestore.instance.collection('matches').doc(matchId);
      final snap = await ref.get();
      final matchData = snap.data();
      await ref.delete();
      if (matchData != null) {
        // Ceilalți jucători și sala află (popup + email); sesiunea cu antrenor se anulează.
        final me = FirebaseAuth.instance.currentUser;
        await NotificationService.matchCancelled(matchId, matchData, byName: (matchData['hostUsername'] ?? me?.email ?? '').toString());
        try {
          await TrainerService.cancelForMatch(matchId);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat cu succes!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare la anulare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showReviewDialog(String matchId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return _VenueReviewDialog(
          matchId: matchId,
          venueId: data['locationId'] ?? '',
          venueName: data['locationName'] ?? 'Sala',
        );
      },
    );
  }

  Future<void> _withdraw(String matchId) async {
    final userUid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final before = (await FirebaseFirestore.instance.collection('matches').doc(matchId).get()).data();
      final result = await BookingService.withdrawFromMatch(matchId, userUid);
      if (result == WithdrawResult.withdrawn && before != null) {
        final String who = List<dynamic>.from(before['joinedPlayers'] ?? [])
            .whereType<Map>()
            .where((p) => p['uid'] == userUid)
            .map((p) => (p['username'] ?? '').toString())
            .firstWhere((_) => true, orElse: () => '');
        final leftArgs = {...NotificationService.matchArgs(before), 'player': who};
        await NotificationService.send(toUid: (before['hostUid'] ?? '').toString(), type: 'match_left', titleKey: 'n.left_title', bodyKey: 'n.left_body', args: leftArgs, matchId: matchId);
        await NotificationService.send(toUid: (before['locationId'] ?? '').toString(), type: 'match_left', titleKey: 'n.left_title', bodyKey: 'n.left_body', args: leftArgs, matchId: matchId);
      }
      if (!mounted) return;
      final String message;
      switch (result) {
        case WithdrawResult.matchDeleted:
          message = 'Meci anulat cu succes!';
          break;
        case WithdrawResult.notFound:
          message = 'Acest meci nu mai există.';
          break;
        case WithdrawResult.withdrawn:
          message = 'Te-ai retras de la masă.';
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showTicketDialog(String matchId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Bilet Check-in', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Prezintă acest cod QR la recepția sălii pentru a confirma check-in-ul.', style: TextStyle(color: AppColors.muted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(12)),
                // SizedBox fix: QrImageView folosește LayoutBuilder, care nu poate fi măsurat
                // de AlertDialog (IntrinsicWidth) fără dimensiune fixă.
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: QrImageView(
                    data: matchId,
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Cod bilet', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              SelectableText(
                CheckInService.formatShortCode(CheckInService.shortCode(matchId)),
                style: TextStyle(color: AppColors.text, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 4),
              ),
              Text(
                'Nu merge scanarea? Spune acest cod sălii.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text('${data['locationName'] ?? 'Sală'} - ${data['date'] ?? ''}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
              Text('${formatHour(data['startHour'])} - ${formatHour(data['endHour'])}', style: TextStyle(color: AppColors.muted)),
            ],
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

  void _addToCalendar(Map<String, dynamic> data) async {
    try {
      final dateStr = data['date'] as String? ?? '2026-01-01'; // fallback
      final startHour = hourValue(data['startHour'], 10);
      final endHour = hourValue(data['endHour'], 11);

      final startDate = dateAtHour(dateStr, startHour);
      final endDate = dateAtHour(dateStr, endHour);

      final Event event = Event(
        title: 'Meci Playhub',
        description: 'Rezervare la ${data['locationName'] ?? 'Sală'}',
        location: '${data['locationName'] ?? 'Sală'}, ${data['city'] ?? ''}',
        startDate: startDate,
        endDate: endDate,
      );

      final success = await Add2Calendar.addEvent2Cal(event);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nu am putut deschide calendarul pe acest dispozitiv.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Funcția Calendar este disponibilă doar pe mobil (iOS/Android).'), backgroundColor: Colors.orange),
        );
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
      final startHour = hourValue(data['startHour']);
      final matchStart = dateAtHour(dateStr, startHour);
      if (matchStart.difference(DateTime.now()).inHours >= 24) {
        canCancel = true;
      }
    } catch (_) {}

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('${data['locationName']} (${data['city']})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.text))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.card2, borderRadius: BorderRadius.circular(8)),
                  child: Text(data['visibility'] == 'private' ? tr('cm.vis_private') : tr('cm.vis_public'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 8),
            Text('${data['date']} | ${formatHour(data['startHour'])} - ${formatHour(data['endHour'])}', style: TextStyle(color: AppColors.muted)),
            Wrap(
              spacing: 16,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.accent),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: Text(tr('mm.details')),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: docId, mode: MatchDetailMode.player)),
                  ),
                ),
                if (!isPast && players.length > 1)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.accent),
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(tr('chat.open_btn')),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: 'match_$docId',
                          isMatchChat: true,
                          matchTitle: '${data['locationName'] ?? ''} · ${data['date'] ?? ''}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr('mm.players_at_table'), style: TextStyle(color: AppColors.muted)),
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
                      color: p['role'] == 'host' ? Colors.yellow : AppColors.muted
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p['username']} (${p['level']})', 
                        style: TextStyle(
                          color: isMe ? AppColors.accent : AppColors.text,
                          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ),
                    if (!isMe) ...[
                      // Chat button
                      IconButton(
                        icon: Icon(Icons.chat_bubble_outline, color: AppColors.accent, size: 18),
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
            }),
            if (players.length < (data['maxPlayers'] ?? 2))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Mai sunt ${(data['maxPlayers'] ?? 2) - players.length} locuri libere...', style: const TextStyle(color: Colors.yellowAccent, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            if (data['status'] == 'cancelled') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(tr('mm.cancelled'), style: const TextStyle(color: Colors.redAccent)),
              ),
            ] else if (isCompleted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('Meci finalizat și puncte acordate!', style: TextStyle(color: Colors.green)),
              ),
              if (!(data['reviewedBy'] as List<dynamic>? ?? []).contains(currentUserUid)) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.yellowAccent,
                      side: const BorderSide(color: Colors.yellowAccent),
                    ),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Lasă o Recenzie Sălii'),
                    onPressed: () => _showReviewDialog(docId, data),
                  ),
                ),
              ],
            ] else if (isPast && (data['status'] == 'matched' || data['status'] == 'reported')) ...[
              if (data['status'] == 'reported') ...[
                if (data['reporterUid'] == currentUserUid)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_empty, color: AppColors.accent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Scorul a fost raportat. Așteptăm confirmarea celorlalți jucători.',
                            style: TextStyle(color: AppColors.accent, fontSize: 13),
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
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                          backgroundColor: AppColors.accent,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: (data['checkedIn'] == true || data['waiting'] == true)
                        ? _CheckInStatusBadge(waiting: data['checkedIn'] != true)
                        : ElevatedButton.icon(
                      onPressed: () => _showTicketDialog(docId, data),
                      icon: const Icon(Icons.qr_code, color: Colors.black),
                      label: const Text('Check-in', style: TextStyle(color: Colors.black)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addToCalendar(data),
                      icon: Icon(Icons.calendar_month, color: AppColors.text),
                      label: Text('Calendar', style: TextStyle(color: AppColors.text)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.muted),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                        onPressed: () => _withdraw(docId),
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
              icon: Icon(Icons.menu, color: AppColors.accent),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          title: const Text('Meciurile Mele'),
          bottom: TabBar(
            indicatorColor: AppColors.accent,
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
              return Center(child: CircularProgressIndicator(color: AppColors.accent));
            }

            final docs = snapshot.data!.docs;
            final upcoming = <QueryDocumentSnapshot>[];
            final past = <QueryDocumentSnapshot>[];

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              // Meciurile anulate nu mai sunt „viitoare": le punem la Past, cu mențiune.
              if (data['status'] == 'cancelled' || _isPast(data)) {
                past.add(doc);
              } else {
                upcoming.add(doc);
              }
            }

            return TabBarView(
              children: [
                upcoming.isEmpty
                    ? Center(child: Text('Niciun meci viitor.', style: TextStyle(color: AppColors.muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: upcoming.length,
                        itemBuilder: (context, index) => _buildMatchCard(upcoming[index].id, upcoming[index].data() as Map<String, dynamic>, false),
                      ),
                past.isEmpty
                    ? Center(child: Text('Niciun meci trecut.', style: TextStyle(color: AppColors.muted)))
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
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent, width: 1),
      ),
      title: Text(
        is2v2 ? 'Raportare Meci 2v2' : 'Raportare Meci 1v1',
        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Câte meciuri ați jucat în total?',
                style: TextStyle(color: AppColors.text70, fontSize: 14),
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
                      activeColor: AppColors.accent,
                      inactiveColor: AppColors.card2,
                      label: _totalMatches.toString(),
                      onChanged: (val) => _updateTotalMatches(val.round()),
                    ),
                  ),
                  Text(
                    _totalMatches.toString(),
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!is2v2) ...[
                Text(
                  'Meciuri câștigate de tine: $_myWins',
                  style: TextStyle(color: AppColors.text70, fontSize: 14),
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
                        inactiveColor: AppColors.card2,
                        label: _myWins.toString(),
                        onChanged: (val) => setState(() => _myWins = val.round()),
                      ),
                    ),
                    Text(
                      '${_totalMatches - _myWins} pierdute',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Scor raportat: $_myWins - ${_totalMatches - _myWins}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 16),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Detalii pentru fiecare meci:',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),
                ...List.generate(_totalMatches, (index) {
                  if (index >= _matches2v2.length) return const SizedBox();
                  final match = _matches2v2[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Meciul ${index + 1}',
                          style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text('Partenerul tău:', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                        DropdownButton<String>(
                          value: match['partnerUid'],
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          style: TextStyle(color: AppColors.text),
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
                            Text('Rezultat:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
                                    child: Text('Câștigat', style: TextStyle(color: AppColors.text, fontSize: 12)),
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
                                    child: Text('Pierdut', style: TextStyle(color: AppColors.text, fontSize: 12)),
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
          child: Text('RENUNȚĂ', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
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

class _VenueReviewDialog extends StatefulWidget {
  final String matchId;
  final String venueId;
  final String venueName;

  const _VenueReviewDialog({
    required this.matchId,
    required this.venueId,
    required this.venueName,
  });

  @override
  State<_VenueReviewDialog> createState() => _VenueReviewDialogState();
}

class _VenueReviewDialogState extends State<_VenueReviewDialog> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (widget.venueId.isEmpty) return;
    setState(() => _isSubmitting = true);

    try {
      final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserUid).get();
      final username = userDoc.data()?['username'] ?? 'Jucător';
      final avatarUrl = userDoc.data()?['avatarUrl'] ?? '';

      final venueRef = FirebaseFirestore.instance.collection('venues').doc(widget.venueId);
      final reviewRef = venueRef.collection('reviews').doc();
      final matchRef = FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final venueDoc = await transaction.get(venueRef);
        if (!venueDoc.exists) throw Exception('Sala nu mai există!');
        final venueData = venueDoc.data() ?? {};

        double ratingTotal = (venueData['ratingTotal'] as num?)?.toDouble() ?? 0.0;
        int ratingCount = (venueData['ratingCount'] as num?)?.toInt() ?? 0;

        ratingTotal += _rating;
        ratingCount += 1;
        double newAverage = ratingTotal / ratingCount;

        transaction.update(venueRef, {
          'ratingTotal': ratingTotal,
          'ratingCount': ratingCount,
          'rating': newAverage,
        });

        transaction.set(reviewRef, {
          'authorUid': currentUserUid,
          'authorUsername': username,
          'authorAvatarUrl': avatarUrl,
          'rating': _rating,
          'comment': _commentController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.update(matchRef, {
          'reviewedBy': FieldValue.arrayUnion([currentUserUid]),
        });
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recenzie adăugată cu succes!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Recenzie pentru ${widget.venueName}', style: TextStyle(color: AppColors.text, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cum a fost experiența?', style: TextStyle(color: AppColors.text70)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.yellowAccent,
                    size: 32,
                  ),
                  onPressed: () => setState(() => _rating = index + 1),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Scrie un comentariu (opțional)...',
                hintStyle: TextStyle(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('ANULEAZĂ', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _isSubmitting ? null : _submitReview,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Text('TRIMITE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _CheckInStatusBadge extends StatelessWidget {
  final bool waiting;
  const _CheckInStatusBadge({required this.waiting});

  @override
  Widget build(BuildContext context) {
    final color = waiting ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(waiting ? Icons.hourglass_top : Icons.check_circle, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            waiting ? 'Sala te-a pus la așteptarea mesei' : 'Check-in efectuat',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
