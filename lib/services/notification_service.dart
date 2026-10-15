import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/hour_utils.dart';

/// Un singur loc prin care aplicația trimite notificări.
///
/// Fiecare notificare este un document în `notifications`. Din el se întâmplă trei lucruri:
/// 1. clopoțelul / lista din aplicație (NotificationsDialog);
/// 2. popup-ul când aplicația e deschisă (NotificationPopups);
/// 3. emailul, trimis de Cloud Function-ul `sendNotificationEmail` (functions/index.js),
///    în limba destinatarului, pe emailul contului lui.
///
/// Textul nu se salvează gata scris: se salvează cheia (`titleKey`/`bodyKey`) și argumentele,
/// ca fiecare destinatar să-l primească în limba lui.
class NotificationService {
  NotificationService._();

  static Future<void> send({
    required String toUid,
    required String type,
    required String titleKey,
    required String bodyKey,
    Map<String, String> args = const {},
    String? matchId,
    Map<String, dynamic> extra = const {},
    bool allowSelf = false,
  }) async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (toUid.isEmpty) return;
      if (!allowSelf && toUid == me?.uid) return; // nu îți notifici propriile acțiuni
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': toUid,
        'fromUid': me?.uid ?? '',
        'fromUsername': '',
        'fromAvatarUrl': '',
        'titleKey': titleKey,
        'bodyKey': bodyKey,
        'args': args,
        'title': 'Playhub',
        'body': '',
        'type': type,
        'status': 'pending',
        if (matchId != null) 'matchId': matchId,
        ...extra,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // O notificare ratată nu trebuie să strice acțiunea principală.
    }
  }

  /// Argumentele comune pentru un meci: {date, time, venue, table}.
  static Map<String, String> matchArgs(Map<String, dynamic> m) => {
        'date': (m['date'] ?? '-').toString(),
        'time': '${formatHour(m['startHour'])} - ${formatHour(m['endHour'])}',
        'venue': (m['locationName'] ?? '-').toString(),
        'table': (m['tableId'] ?? '-').toString(),
      };

  /// Anunță toți ceilalți jucători (și sala) că meciul a fost anulat.
  static Future<void> matchCancelled(String matchId, Map<String, dynamic> m, {required String byName}) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final args = {...matchArgs(m), 'by': byName};
    final Set<String> targets = {
      ...List<dynamic>.from(m['joinedUids'] ?? []).map((e) => e.toString()),
      (m['locationId'] ?? '').toString(),
    }..remove('');
    for (final uid in targets) {
      if (uid == me) continue;
      await send(
        toUid: uid,
        type: 'match_cancel',
        titleKey: 'n.cancel_title',
        bodyKey: 'n.cancel_body',
        args: args,
        matchId: matchId,
      );
    }
  }
}
