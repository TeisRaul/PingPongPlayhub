import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/hour_utils.dart';
import 'notification_service.dart';

/// Un interval în care sala nu primește rezervări (mentenanță, eveniment privat etc.).
/// Se salvează în `venues/{id}.blockedSlots`.
class BlockedSlot {
  final String id;
  final String date; // yyyy-MM-dd
  final double startHour;
  final double endHour;
  final List<int> tableIds; // gol = toate mesele
  final String? sport; // null = toate sporturile
  final String reason;

  const BlockedSlot({
    required this.id,
    required this.date,
    required this.startHour,
    required this.endHour,
    required this.tableIds,
    required this.sport,
    required this.reason,
  });

  factory BlockedSlot.fromMap(Map<String, dynamic> m) => BlockedSlot(
        id: (m['id'] ?? '').toString(),
        date: (m['date'] ?? '').toString(),
        startHour: (m['startHour'] as num?)?.toDouble() ?? 0,
        endHour: (m['endHour'] as num?)?.toDouble() ?? 24,
        tableIds: List<dynamic>.from(m['tableIds'] ?? const []).map((e) => (e as num).toInt()).toList(),
        sport: (m['sport'] as String?)?.isEmpty == true ? null : m['sport'] as String?,
        reason: (m['reason'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'startHour': startHour,
        'endHour': endHour,
        'tableIds': tableIds,
        'sport': sport,
        'reason': reason,
      };

  bool get allTables => tableIds.isEmpty;
}

/// Rezultatul verificării blocărilor pentru un interval.
class BlockResult {
  final bool allTables;
  final Set<int> tables;
  const BlockResult(this.allTables, this.tables);
  static const none = BlockResult(false, {});
}

class MassCancelResult {
  final int cancelled;
  final int refunded;
  final int notified;
  const MassCancelResult(this.cancelled, this.refunded, this.notified);
}

class VenueTools {
  VenueTools._();

  static final _ymd = DateFormat('yyyy-MM-dd');

  static List<BlockedSlot> parseBlocked(dynamic raw) {
    if (raw is! List) return [];
    final out = <BlockedSlot>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          out.add(BlockedSlot.fromMap(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    return out;
  }

  /// Sporturile sălii.
  static List<String> sports(Map<String, dynamic>? data) {
    final l = List<String>.from(data?['supportedSports'] ?? const ['ping_pong']);
    return l.isEmpty ? ['ping_pong'] : l;
  }

  /// Mesele/terenurile sălii pentru un sport: [{tableId, name, type}] (din plan sau din numărul de resurse).
  static List<Map<String, dynamic>> tablesFor(Map<String, dynamic>? data, String sport) {
    if (data == null) return [];
    final out = <Map<String, dynamic>>[];
    if (data['layouts'] is Map) {
      final raw = (data['layouts'] as Map)[sport];
      if (raw is List) {
        for (final t in raw) {
          if (t is Map) out.add(Map<String, dynamic>.from(t));
        }
      }
    } else if (sport == 'ping_pong' && data['customTables'] is List) {
      for (final t in data['customTables'] as List) {
        if (t is Map) out.add(Map<String, dynamic>.from(t));
      }
    } else {
      final rps = data['resourcesPerSport'];
      final Map? r = rps is Map ? rps[sport] as Map? : null;
      final int indoor = (r?['indoor'] as num?)?.toInt() ?? 4;
      final int outdoor = (r?['outdoor'] as num?)?.toInt() ?? 0;
      int id = 1;
      for (int i = 0; i < indoor; i++) {
        out.add({'tableId': id++, 'name': 'Teren/Masă ${i + 1}', 'type': 'indoor'});
      }
      for (int i = 0; i < outdoor; i++) {
        out.add({'tableId': id++, 'name': 'Teren/Masă ${i + 1} Out', 'type': 'outdoor'});
      }
    }
    out.sort((x, y) => ((x['tableId'] as num?) ?? 0).compareTo((y['tableId'] as num?) ?? 0));
    return out;
  }

  static String tableName(Map<String, dynamic> t) => (t['name'] ?? 'Masa ${t['tableId']}').toString();

  /// Ce mese sunt blocate în [dateStr] între [start] și [end] (pentru [sport], dacă e dat).
  static BlockResult blockFor(Map<String, dynamic>? venueData, String dateStr, num start, num end, {String? sport}) {
    if (venueData == null) return BlockResult.none;
    bool all = false;
    final tables = <int>{};
    for (final b in parseBlocked(venueData['blockedSlots'])) {
      if (b.date != dateStr) continue;
      if (b.sport != null && sport != null && b.sport != sport) continue;
      if (!(start < b.endHour && b.startHour < end)) continue;
      if (b.allTables) {
        all = true;
      } else {
        tables.addAll(b.tableIds);
      }
    }
    return BlockResult(all, tables);
  }

  /// Meciurile active ale sălii care cad în filtrul dat (zile consecutive, interval orar, mese).
  static Future<List<Map<String, dynamic>>> affectedMatches({
    required String venueId,
    required DateTime from,
    required DateTime to,
    required double startHour,
    required double endHour,
    String? sport,
    List<int> tableIds = const [],
  }) async {
    final out = <Map<String, dynamic>>[];
    var day = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    int guard = 0;
    while (!day.isAfter(last) && guard++ < 62) {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: venueId)
          .where('date', isEqualTo: _ymd.format(day))
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        final status = (m['status'] ?? '').toString();
        if (status == 'cancelled' || status == 'completed' || status == 'finished') continue;
        final s = hourValue(m['startHour']);
        final e = hourValue(m['endHour']);
        if (!(s < endHour && startHour < e)) continue;
        if (sport != null && (m['sport'] ?? 'ping_pong') != sport) continue;
        final t = (m['tableId'] as num?)?.toInt() ?? 0;
        if (tableIds.isNotEmpty && !tableIds.contains(t)) continue;
        m['docId'] = d.id;
        out.add(m);
      }
      day = day.add(const Duration(days: 1));
    }
    out.sort((a, b) {
      final c = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
      if (c != 0) return c;
      return hourValue(a['startHour']).compareTo(hourValue(b['startHour']));
    });
    return out;
  }

  /// Anulează rezervările (cu rambursare dacă au fost plătite cu cardul) și anunță jucătorii.
  static Future<MassCancelResult> cancelMatches({
    required List<Map<String, dynamic>> matches,
    required String venueName,
    required String reason,
    bool massCancel = false,
  }) async {
    int cancelled = 0, refunded = 0, notified = 0;
    for (final m in matches) {
      final String id = m['docId'].toString();
      final String paymentMethod = (m['paymentMethod'] ?? '').toString();
      final String paymentStatus = (m['paymentStatus'] ?? '').toString();
      final double price = (m['price'] as num?)?.toDouble() ?? 0.0;
      final updates = <String, dynamic>{
        'status': 'cancelled',
        'cancelledBy': 'venue',
        'cancelReason': reason,
        if (massCancel) 'massCancel': true,
      };
      if (paymentMethod.contains('Card') && paymentStatus == 'confirmed') {
        updates['paymentStatus'] = 'refunded';
        updates['refundedAmount'] = price;
        refunded++;
      }
      await FirebaseFirestore.instance.collection('matches').doc(id).update(updates);
      cancelled++;

      final args = {
        ...NotificationService.matchArgs({...m, 'locationName': m['locationName'] ?? venueName}),
        'reason': reason.isEmpty ? '-' : reason,
      };
      final targets = <String>{
        ...List<dynamic>.from(m['joinedUids'] ?? const []).map((e) => e.toString()),
        (m['hostUid'] ?? '').toString(),
      }..removeWhere((u) => u.isEmpty || u.startsWith('offline_') || u == (m['locationId'] ?? '').toString());
      for (final uid in targets) {
        await NotificationService.send(
          toUid: uid,
          type: 'match_cancel',
          titleKey: 'n.mass_cancel_title',
          bodyKey: reason.isEmpty ? 'n.mass_cancel_body_noreason' : 'n.mass_cancel_body',
          args: args,
          matchId: id,
        );
        notified++;
      }
    }
    return MassCancelResult(cancelled, refunded, notified);
  }

  /// Adaugă un interval blocat în profilul sălii.
  static Future<void> addBlockedSlots(String venueId, List<BlockedSlot> slots) async {
    if (slots.isEmpty) return;
    final ref = FirebaseFirestore.instance.collection('venues').doc(venueId);
    await ref.update({'blockedSlots': FieldValue.arrayUnion(slots.map((s) => s.toMap()).toList())});
  }

  static Future<void> removeBlockedSlot(String venueId, BlockedSlot slot) async {
    final ref = FirebaseFirestore.instance.collection('venues').doc(venueId);
    await ref.update({'blockedSlots': FieldValue.arrayRemove([slot.toMap()])});
  }

  /// Mută o rezervare pe altă masă / alt interval și anunță jucătorii.
  /// Verifică conflictele; întoarce un mesaj de eroare (sau null dacă a reușit).
  static Future<String?> moveMatch({
    required Map<String, dynamic> match,
    required int newTableId,
    required double newStart,
    required double newEnd,
    required String venueName,
    required Map<String, dynamic>? venueData,
    List<Map<String, dynamic>> dayMatches = const [],
  }) async {
    final String id = match['docId'].toString();
    final String dateStr = (match['date'] ?? '').toString();
    final String? sport = match['sport']?.toString();

    for (final o in dayMatches) {
      if (o['docId'] == id) continue;
      if ((o['status'] ?? '') == 'cancelled') continue;
      if ((o['sport'] ?? 'ping_pong') != (sport ?? 'ping_pong')) continue;
      if (((o['tableId'] as num?)?.toInt() ?? 0) != newTableId) continue;
      if (newStart < hourValue(o['endHour']) && hourValue(o['startHour']) < newEnd) {
        return 'conflict';
      }
    }
    final b = blockFor(venueData, dateStr, newStart, newEnd, sport: sport);
    if (b.allTables || b.tables.contains(newTableId)) return 'blocked';

    await FirebaseFirestore.instance.collection('matches').doc(id).update({
      'tableId': newTableId,
      'startHour': newStart,
      'endHour': newEnd,
      'movedByVenue': true,
    });

    final oldTable = (match['tableId'] ?? '-').toString();
    final oldTime = '${formatHour(match['startHour'])} - ${formatHour(match['endHour'])}';
    final args = {
      'venue': venueName,
      'date': dateStr,
      'old_time': oldTime,
      'new_time': '${formatHour(newStart)} - ${formatHour(newEnd)}',
      'old_table': oldTable,
      'new_table': '$newTableId',
    };
    final targets = <String>{
      ...List<dynamic>.from(match['joinedUids'] ?? const []).map((e) => e.toString()),
      (match['hostUid'] ?? '').toString(),
    }..removeWhere((u) => u.isEmpty || u.startsWith('offline_') || u == (match['locationId'] ?? '').toString());
    for (final uid in targets) {
      await NotificationService.send(
        toUid: uid,
        type: 'match_moved',
        titleKey: 'n.moved_title',
        bodyKey: 'n.moved_body',
        args: args,
        matchId: id,
      );
    }
    return null;
  }
}
