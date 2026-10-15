import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/strings.dart';
import 'booking_service.dart';
import 'notification_service.dart';
import 'trainer_service.dart';

/// Acțiunile "Acceptă / Refuză" din notificări (folosite de lista din aplicație și de popup).
class NotificationActions {
  NotificationActions._();

  static final _db = FirebaseFirestore.instance;

  static Future<void> _setStatus(String id, String status) =>
      _db.collection('notifications').doc(id).update({'status': status});

  /// Tipurile care au butoane Acceptă / Refuză.
  static bool isActionable(String type) => type == 'join_request' || type == 'trainer_request';

  /// Întoarce mesajul (deja tradus) de afișat după decizie.
  static Future<String> decide(String notifId, Map<String, dynamic> n, {required bool accept}) async {
    switch (n['type']) {
      case 'join_request':
        return _decideJoin(notifId, n, accept);
      case 'trainer_request':
        return _decideTrainer(notifId, n, accept);
    }
    return '';
  }

  // --- Cerere de alăturare la un meci (decide gazda) ---
  static Future<String> _decideJoin(String notifId, Map<String, dynamic> n, bool accept) async {
    final String matchId = (n['matchId'] ?? '').toString();
    final Map<String, dynamic> player = Map<String, dynamic>.from(n['player'] ?? {});
    final String playerUid = (player['uid'] ?? n['fromUid'] ?? '').toString();
    if (matchId.isEmpty || playerUid.isEmpty) {
      await _setStatus(notifId, 'invalid');
      return tr('n.err_invalid');
    }

    final matchRef = _db.collection('matches').doc(matchId);
    final matchSnap = await matchRef.get();
    if (!matchSnap.exists) {
      await _setStatus(notifId, 'invalid');
      return tr('n.err_match_gone');
    }
    final match = matchSnap.data()!;
    final args = {
      ...NotificationService.matchArgs(match),
      'host': (match['hostUsername'] ?? '').toString(),
    };

    if (!accept) {
      await matchRef.update({'joinRequestUids': FieldValue.arrayRemove([playerUid])});
      await _setStatus(notifId, 'declined');
      await NotificationService.send(
        toUid: playerUid,
        type: 'join_declined',
        titleKey: 'n.join_no_title',
        bodyKey: 'n.join_no_body',
        args: args,
        matchId: matchId,
      );
      return tr('n.join_declined_snack');
    }

    final result = await BookingService.joinMatch(matchId, player);
    if (result == JoinResult.joined || result == JoinResult.alreadyJoined) {
      await matchRef.update({'joinRequestUids': FieldValue.arrayRemove([playerUid])});
      await _setStatus(notifId, 'accepted');
      if (result == JoinResult.joined) {
        await NotificationService.send(
          toUid: playerUid,
          type: 'join_accepted',
          titleKey: 'n.join_ok_title',
          bodyKey: 'n.join_ok_body',
          args: args,
          matchId: matchId,
        );
      }
      return tr('n.join_accepted_snack');
    }
    await _setStatus(notifId, result == JoinResult.full ? 'full' : 'invalid');
    return result == JoinResult.full ? tr('n.err_full') : tr('n.err_match_gone');
  }

  // --- Cerere de sesiune cu antrenor (decide antrenorul) ---
  static Future<String> _decideTrainer(String notifId, Map<String, dynamic> n, bool accept) async {
    final String reservationId = (n['reservationId'] ?? '').toString();
    if (reservationId.isEmpty) {
      await _setStatus(notifId, 'invalid');
      return tr('n.err_invalid');
    }
    final snap = await _db.collection('reservations').doc(reservationId).get();
    if (!snap.exists) {
      await _setStatus(notifId, 'invalid');
      return tr('n.err_invalid');
    }
    final res = {...snap.data()!, 'id': snap.id};
    if (res['status'] != TrainerStatus.pending) {
      await _setStatus(notifId, 'read');
      return tr('n.err_already_answered');
    }
    try {
      await TrainerService.respond(res, accept: accept);
    } catch (e) {
      if (e.toString().contains('overlap')) return tr('tr.err_overlap');
      rethrow;
    }
    await _setStatus(notifId, accept ? 'accepted' : 'declined');
    return accept ? tr('tr.accepted_snack') : tr('tr.declined_snack');
  }
}
