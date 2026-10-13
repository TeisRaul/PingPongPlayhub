import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/hour_utils.dart';

enum TableState { free, occupied, training, current }

class TableOption {
  final int id;
  final String name;
  final String type; // indoor / outdoor / training
  final TableState state;

  /// Pentru mesele ocupate: cine o are și în ce interval.
  final String? detail;

  const TableOption({
    required this.id,
    required this.name,
    required this.type,
    required this.state,
    this.detail,
  });
}

/// Mesele unei săli pe intervalul unei rezervări: care sunt libere și care nu,
/// plus mutarea unei rezervări pe altă masă.
class TableService {
  TableService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Construiește lista meselor (logică pură, fără acces la baza de date).
  ///
  /// [customTables] = planul sălii (dacă există); altfel mesele sunt numerotate
  /// 1..[sequentialCount], la fel ca la crearea rezervării.
  static List<TableOption> buildOptions({
    required String tableType,
    required List<Map<String, dynamic>> customTables,
    required int sequentialCount,
    required int? currentId,
    required Map<int, String> occupiedBy,
    required Set<int> trainingBlocked,
  }) {
    final result = <TableOption>[];

    TableState stateOf(int id) {
      if (id == currentId) return TableState.current;
      if (occupiedBy.containsKey(id)) return TableState.occupied;
      if (trainingBlocked.contains(id)) return TableState.training;
      return TableState.free;
    }

    if (customTables.isNotEmpty) {
      for (final t in customTables) {
        final id = (t['tableId'] as num?)?.toInt();
        if (id == null) continue;
        final type = (t['type'] ?? 'indoor').toString();
        final visible = tableType == 'outdoor' ? type == 'outdoor' : (type == 'indoor' || type == 'training');
        if (!visible) continue;
        result.add(TableOption(
          id: id,
          name: (t['name'] ?? 'Masa $id').toString(),
          type: type,
          state: stateOf(id),
          detail: occupiedBy[id],
        ));
      }
    } else {
      for (var id = 1; id <= sequentialCount; id++) {
        result.add(TableOption(
          id: id,
          name: 'Masa $id',
          type: tableType,
          state: stateOf(id),
          detail: occupiedBy[id],
        ));
      }
    }

    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  static bool _trainingActiveAt(num hour, int weekday, Map<String, dynamic> config) {
    if (config['enabled'] == false) return false;
    final days = config['weekdays'];
    if (days is! List || !days.contains(weekday)) return false;
    final start = (config['startHour'] as num?) ?? 17;
    final end = (config['endHour'] as num?) ?? 19;
    return hour >= start && hour < end;
  }

  /// Mesele sălii pe intervalul rezervării [matchId], cu starea fiecăreia.
  static Future<List<TableOption>> optionsForMatch(String matchId, Map<String, dynamic> match) async {
    final venueId = (match['locationId'] ?? '').toString();
    final date = (match['date'] ?? '').toString();
    final start = hourValue(match['startHour']);
    final end = hourValue(match['endHour']);
    final sport = (match['sport'] ?? 'ping_pong').toString();
    final tableType = (match['tableType'] ?? 'indoor').toString();
    final currentId = (match['tableId'] as num?)?.toInt();

    if (venueId.isEmpty) return [];

    final venueDoc = await _db.collection('venues').doc(venueId).get();
    final venue = venueDoc.data() ?? <String, dynamic>{};
    if (venue['isPublic'] == true) return [];

    // Planul sălii (la fel ca în ecranul de creare a rezervării).
    var custom = <Map<String, dynamic>>[];
    final layouts = venue['layouts'];
    if (layouts is Map) {
      final forSport = layouts[sport];
      if (forSport is List) {
        custom = forSport.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } else if (venue['customTables'] is List && sport == 'ping_pong') {
      custom = (venue['customTables'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    // Câte mese numerotate simplu are sala.
    var count = 0;
    final rps = venue['resourcesPerSport'];
    if (rps is Map && rps[sport] is Map) {
      count = ((rps[sport] as Map)[tableType] as num?)?.toInt() ?? 0;
    } else if (tableType == 'outdoor') {
      count = (venue['outdoorTables'] as num?)?.toInt() ?? 0;
    } else {
      count = (venue['indoorTables'] as num?)?.toInt() ?? (venue['totalTables'] as num?)?.toInt() ?? 4;
    }

    // Mesele luate de alte rezervări în același interval.
    final occupied = <int, String>{};
    final snap = await _db
        .collection('matches')
        .where('locationId', isEqualTo: venueId)
        .where('date', isEqualTo: date)
        .get();
    for (final d in snap.docs) {
      if (d.id == matchId) continue;
      final m = d.data();
      if (m['status'] == 'cancelled' || m['status'] == 'completed') continue;
      final id = (m['tableId'] as num?)?.toInt();
      if (id == null) continue;
      final s = hourValue(m['startHour']);
      final e = hourValue(m['endHour']);
      if (start < e && s < end) {
        occupied[id] = '${m['hostUsername'] ?? 'rezervat'} ${formatHour(s)}-${formatHour(e)}';
      }
    }

    // Mesele rezervate pentru antrenamente în acest interval.
    final training = <int>{};
    final config = venue['trainingConfig'];
    final weekday = DateTime.tryParse(date)?.weekday;
    if (config is Map && weekday != null) {
      final cfg = Map<String, dynamic>.from(config);
      var active = false;
      for (num h = start; h < end; h += 0.5) {
        if (_trainingActiveAt(h, weekday, cfg)) {
          active = true;
          break;
        }
      }
      if (active) {
        for (final t in custom) {
          final id = (t['tableId'] as num?)?.toInt();
          if (id != null && t['type'] == 'training') training.add(id);
        }
      }
    }

    return buildOptions(
      tableType: tableType,
      customTables: custom,
      sequentialCount: count,
      currentId: currentId,
      occupiedBy: occupied,
      trainingBlocked: training,
    );
  }

  /// Mută rezervarea pe [target] și anunță jucătorii. Returnează `false` dacă
  /// masa s-a ocupat între timp.
  static Future<bool> changeTable(
    String matchId,
    Map<String, dynamic> match,
    TableOption target,
  ) async {
    // Verificăm din nou, ca să nu mutăm peste o rezervare apărută între timp.
    final fresh = await optionsForMatch(matchId, match);
    final still = fresh.where((o) => o.id == target.id && o.state == TableState.free);
    if (still.isEmpty) return false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final oldId = match['tableId'];
    final batch = _db.batch();

    batch.update(_db.collection('matches').doc(matchId), {
      'tableId': target.id,
      if (target.type == 'indoor' || target.type == 'outdoor') 'tableType': target.type,
      'previousTableId': oldId,
      'tableChangedAt': FieldValue.serverTimestamp(),
      if (uid != null) 'tableChangedBy': uid,
    });

    final players = List<dynamic>.from(match['joinedUids'] ?? []);
    for (final p in players) {
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'toUid': p,
        'fromUid': 'system',
        'fromUsername': 'Sala',
        'fromAvatarUrl': '',
        'title': 'Masa a fost schimbată',
        'body': 'Sala ți-a mutat rezervarea din ${match['date']} '
            '(${formatHour(match['startHour'])}-${formatHour(match['endHour'])}) '
            'pe ${target.name}.',
        'type': 'table_changed',
        'status': 'pending',
        'matchId': matchId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return true;
  }
}
