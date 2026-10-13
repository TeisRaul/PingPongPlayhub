import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/hour_utils.dart';

enum JoinResult { joined, alreadyJoined, full, unavailable }

enum WithdrawResult { withdrawn, matchDeleted, notFound }

/// Operații pe `matches` care trebuie să fie sigure când mai mulți jucători
/// acționează în același timp (alăturare, retragere, rezervarea unei mese).
class BookingService {
  BookingService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Mesajul pentru jucător când alăturarea nu a reușit.
  static String joinMessage(JoinResult result) {
    switch (result) {
      case JoinResult.alreadyJoined:
        return 'Ești deja înscris la acest meci!';
      case JoinResult.full:
        return 'Masa este deja plină.';
      case JoinResult.unavailable:
        return 'Meciul nu mai este disponibil.';
      case JoinResult.joined:
        return 'Te-ai alăturat cu succes!';
    }
  }

  /// Adaugă jucătorul la meci, într-o tranzacție: verifică locurile libere pe
  /// datele curente din server, nu pe cele afișate pe ecran.
  static Future<JoinResult> joinMatch(String matchId, Map<String, dynamic> player) {
    final ref = _db.collection('matches').doc(matchId);
    return _db.runTransaction<JoinResult>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return JoinResult.unavailable;
      final data = snap.data() ?? {};

      final status = data['status'];
      if (status == 'cancelled' || status == 'completed') return JoinResult.unavailable;

      final players = List<dynamic>.from(data['joinedPlayers'] ?? []);
      final uids = List<dynamic>.from(data['joinedUids'] ?? []);
      final uid = player['uid'];

      if (uids.contains(uid)) return JoinResult.alreadyJoined;

      final maxPlayers = (data['maxPlayers'] as num?)?.toInt() ?? 2;
      if (players.length >= maxPlayers) return JoinResult.full;

      players.add(player);
      uids.add(uid);

      tx.update(ref, {
        'status': players.length >= maxPlayers ? 'matched' : 'open',
        'joinedPlayers': players,
        'joinedUids': uids,
      });
      return JoinResult.joined;
    });
  }

  /// Retrage jucătorul dintr-un meci (tranzacție). Dacă pleacă gazda, locul ei
  /// îl ia primul jucător rămas; dacă nu rămâne nimeni, meciul se șterge.
  static Future<WithdrawResult> withdrawFromMatch(String matchId, String uid) {
    final ref = _db.collection('matches').doc(matchId);
    return _db.runTransaction<WithdrawResult>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return WithdrawResult.notFound;
      final data = snap.data() ?? {};

      final players = List<dynamic>.from(data['joinedPlayers'] ?? []);
      final uids = List<dynamic>.from(data['joinedUids'] ?? []);
      players.removeWhere((p) => p is Map && p['uid'] == uid);
      uids.remove(uid);

      final wasHost = data['hostUid'] == uid;
      if (wasHost && players.isEmpty) {
        tx.delete(ref);
        return WithdrawResult.matchDeleted;
      }

      final updates = <String, dynamic>{
        'joinedPlayers': players,
        'joinedUids': uids,
        'status': 'open',
      };

      if (wasHost) {
        final newHost = Map<String, dynamic>.from(players.first as Map);
        newHost['role'] = 'host';
        players[0] = newHost;
        updates['hostUid'] = newHost['uid'];
        updates['hostUsername'] = newHost['username'];
        updates['hostAvatarUrl'] = newHost['avatarUrl'];
        updates['hostRating'] = newHost['rating'];
        updates['hostLevel'] = newHost['level'];
      }

      tx.update(ref, updates);
      return WithdrawResult.withdrawn;
    });
  }

  /// Meciurile active care ocupă aceeași masă în intervalul dat.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _conflicts({
    required String venueId,
    required String date,
    required dynamic tableId,
    required double start,
    required double end,
  }) async {
    final snap = await _db
        .collection('matches')
        .where('locationId', isEqualTo: venueId)
        .where('date', isEqualTo: date)
        .get(const GetOptions(source: Source.server));

    return snap.docs.where((d) {
      final m = d.data();
      if (m['status'] == 'cancelled') return false;
      if (m['tableId'] != tableId) return false;
      final s = hourValue(m['startHour']);
      final e = hourValue(m['endHour']);
      return start < e && s < end;
    }).toList();
  }

  static int _createdMicros(Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return ts is Timestamp ? ts.microsecondsSinceEpoch : 1 << 62;
  }

  /// Creează rezervarea și returnează id-ul ei, sau `null` dacă masa e deja
  /// ocupată în acel interval.
  ///
  /// Firestore nu poate bloca o interogare într-o tranzacție, așa că verificarea
  /// se face înainte și după scriere. Dacă doi jucători rezervă simultan, rămâne
  /// meciul creat primul (la egalitate, cel cu id-ul mai mic); celălalt se șterge.
  static Future<String?> createMatchChecked(Map<String, dynamic> matchData) async {
    final venueId = (matchData['locationId'] ?? '').toString();
    final date = (matchData['date'] ?? '').toString();
    final tableId = matchData['tableId'];
    final start = hourValue(matchData['startHour']);
    final end = hourValue(matchData['endHour']);

    // Fără masă aleasă (ex. locații publice) nu există ce să se suprapună.
    if (tableId == null || venueId.isEmpty || date.isEmpty) {
      final ref = await _db.collection('matches').add(matchData);
      return ref.id;
    }

    final before = await _conflicts(
        venueId: venueId, date: date, tableId: tableId, start: start, end: end);
    if (before.isNotEmpty) return null;

    final ref = await _db.collection('matches').add(matchData);

    final after = await _conflicts(
        venueId: venueId, date: date, tableId: tableId, start: start, end: end);
    after.sort((a, b) {
      final byTime = _createdMicros(a.data()).compareTo(_createdMicros(b.data()));
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

    if (after.isNotEmpty && after.first.id != ref.id) {
      await ref.delete();
      return null;
    }
    return ref.id;
  }
}
