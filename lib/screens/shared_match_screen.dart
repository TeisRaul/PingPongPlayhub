import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/sports.dart';
import '../l10n/strings.dart';
import '../services/booking_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';
import '../utils/level_utils.dart';
import '../utils/player_name.dart';
import 'match_detail_screen.dart';

/// Ce vede cineva care deschide un meci dintr-un link primit: detaliile și butonul de alăturare.
class SharedMatchScreen extends StatefulWidget {
  final String matchId;
  const SharedMatchScreen({super.key, required this.matchId});

  @override
  State<SharedMatchScreen> createState() => _SharedMatchScreenState();
}

class _SharedMatchScreenState extends State<SharedMatchScreen> {
  bool _busy = false;

  bool _isOver(Map<String, dynamic> m) {
    final status = (m['status'] ?? 'open').toString();
    if (status == 'cancelled' || status == 'completed') return true;
    try {
      final end = dateAtHour(m['date'].toString(), hourValue(m['endHour']));
      return end.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  void _snack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _join(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final name = playerDisplayName(userData, email: user.email, fallback: tr('common.unknown_player'));
      final rating = userData['rating'] ?? 0;
      final player = {
        'uid': user.uid,
        'username': name,
        'avatarUrl': userData['avatarUrl'],
        'rating': rating,
        'level': LevelUtils.getLevelDetails(rating)['levelName'],
        'role': 'guest',
      };
      final hostUid = (data['hostUid'] ?? '').toString();
      final args = {
        ...NotificationService.matchArgs(data),
        'player': name,
        'host': (data['hostUsername'] ?? '').toString(),
      };

      if (data['requireApproval'] == true && hostUid.isNotEmpty && hostUid != user.uid) {
        final already = List<dynamic>.from(data['joinRequestUids'] ?? []);
        if (already.contains(user.uid)) {
          _snack(tr('n.request_already'), color: Colors.orangeAccent);
          return;
        }
        await FirebaseFirestore.instance.collection('matches').doc(widget.matchId).update({
          'joinRequestUids': FieldValue.arrayUnion([user.uid]),
        });
        await NotificationService.send(
          toUid: hostUid,
          type: 'join_request',
          titleKey: 'n.join_req_title',
          bodyKey: 'n.join_req_body',
          args: args,
          matchId: widget.matchId,
          extra: {'player': player, 'fromUsername': name, 'fromAvatarUrl': userData['avatarUrl'] ?? ''},
        );
        _snack(tr('share.done_requested'), color: Colors.green);
        return;
      }

      final result = await BookingService.joinMatch(widget.matchId, player);
      if (result != JoinResult.joined) {
        _snack(BookingService.joinMessage(result), color: Colors.orangeAccent);
        return;
      }
      await NotificationService.send(
        toUid: hostUid,
        type: 'match_join',
        titleKey: 'n.joined_title',
        bodyKey: 'n.joined_body',
        args: args,
        matchId: widget.matchId,
      );
      _snack(tr('share.done_joined'), color: Colors.green);
    } catch (e) {
      _snack('$e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text(tr('share.title'), style: TextStyle(color: AppColors.text, fontSize: 18)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('matches').doc(widget.matchId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _message(tr('share.not_found'));
          }
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: AppColors.accent));
          final doc = snap.data!;
          if (!doc.exists) return _message(tr('share.not_found'));
          return _body(doc.data() ?? <String, dynamic>{});
        },
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 16)),
        ),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: AppColors.text))),
          ],
        ),
      );

  Widget _body(Map<String, dynamic> m) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final players = List<dynamic>.from(m['joinedPlayers'] ?? []);
    final joinedUids = List<dynamic>.from(m['joinedUids'] ?? []);
    final maxPlayers = (m['maxPlayers'] as num?)?.toInt() ?? 2;
    final isIn = uid != null && joinedUids.contains(uid);
    final requested = uid != null && List<dynamic>.from(m['joinRequestUids'] ?? []).contains(uid);
    final private = m['visibility'] == 'private';
    final over = _isOver(m);
    final full = players.length >= maxPlayers;
    final needsApproval = m['requireApproval'] == true;

    String? blocker;
    if (isIn) {
      blocker = tr('share.joined');
    } else if (over) {
      blocker = tr('share.over');
    } else if (private) {
      blocker = tr('share.private_match');
    } else if (full) {
      blocker = tr('share.full');
    } else if (requested) {
      blocker = tr('n.request_already');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (m['locationName'] ?? '').toString(),
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if ((m['city'] ?? '').toString().isNotEmpty)
                Text(m['city'].toString(), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              _row(Icons.calendar_month, '${m['date'] ?? ''}  |  ${formatHour(m['startHour'])} - ${formatHour(m['endHour'])}'),
              _row(Icons.sports_tennis, sportLabel((m['sport'] ?? '-').toString())),
              _row(Icons.person_outline, tr('share.host', {'name': (m['hostUsername'] ?? '-').toString()})),
              _row(Icons.groups_outlined, tr('share.players', {'n': '${players.length}', 'max': '$maxPlayers'})),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (blocker != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(blocker, style: TextStyle(color: AppColors.text70)),
          ),
        if (isIn && !over) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: widget.matchId, mode: MatchDetailMode.player)),
              ),
              child: Text(tr('share.view'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        if (blocker == null)
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
              onPressed: _busy ? null : () => _join(m),
              child: _busy
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                  : Text(needsApproval ? tr('share.request') : tr('share.join'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
