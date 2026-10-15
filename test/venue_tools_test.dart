import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/services/venue_tools.dart';

Map<String, dynamic> _block({
  String date = '2026-10-20',
  double start = 10,
  double end = 12,
  List<int> tables = const [],
  String? sport,
}) =>
    {
      'id': 'b',
      'date': date,
      'startHour': start,
      'endHour': end,
      'tableIds': tables,
      'sport': sport,
      'reason': 'test',
    };

Map<String, dynamic> _match(String id, int table, double s, double e, {String sport = 'ping_pong', String status = 'open'}) => {
      'docId': id,
      'date': '2026-10-20',
      'tableId': table,
      'startHour': s,
      'endHour': e,
      'sport': sport,
      'status': status,
    };

void main() {
  group('VenueTools.blockFor - intervale blocate', () {
    test('o masă blocată', () {
      final v = {'blockedSlots': [_block(tables: [2])]};
      final r = VenueTools.blockFor(v, '2026-10-20', 11, 13);
      expect(r.allTables, isFalse);
      expect(r.tables, {2});
    });

    test('toate mesele blocate (listă goală)', () {
      final v = {'blockedSlots': [_block()]};
      expect(VenueTools.blockFor(v, '2026-10-20', 10, 11).allTables, isTrue);
    });

    test('intervale care doar se ating nu se suprapun', () {
      final v = {'blockedSlots': [_block(start: 10, end: 12)]};
      expect(VenueTools.blockFor(v, '2026-10-20', 12, 13).allTables, isFalse);
      expect(VenueTools.blockFor(v, '2026-10-20', 9, 10).allTables, isFalse);
      expect(VenueTools.blockFor(v, '2026-10-20', 11.5, 12.5).allTables, isTrue);
    });

    test('altă zi: nimic blocat', () {
      final v = {'blockedSlots': [_block()]};
      final r = VenueTools.blockFor(v, '2026-10-21', 10, 12);
      expect(r.allTables, isFalse);
      expect(r.tables, isEmpty);
    });

    test('blocarea pe sport nu afectează alte sporturi', () {
      final v = {'blockedSlots': [_block(sport: 'tenis')]};
      expect(VenueTools.blockFor(v, '2026-10-20', 10, 12, sport: 'ping_pong').allTables, isFalse);
      expect(VenueTools.blockFor(v, '2026-10-20', 10, 12, sport: 'tenis').allTables, isTrue);
      expect(VenueTools.blockFor(v, '2026-10-20', 10, 12).allTables, isTrue); // sport necunoscut: se blochează
    });

    test('mai multe blocări se combină', () {
      final v = {
        'blockedSlots': [_block(tables: [1]), _block(tables: [3])],
      };
      expect(VenueTools.blockFor(v, '2026-10-20', 10, 12).tables, {1, 3});
    });

    test('fără date despre sală sau fără blocări', () {
      expect(VenueTools.blockFor(null, '2026-10-20', 10, 12).allTables, isFalse);
      expect(VenueTools.blockFor(const {}, '2026-10-20', 10, 12).tables, isEmpty);
    });

    test('parseBlocked ignoră intrările stricate', () {
      final list = VenueTools.parseBlocked([_block(), 'x', null, {'tableIds': ['a']}]);
      expect(list.length, 1);
      expect(VenueTools.parseBlocked(null), isEmpty);
    });

    test('BlockedSlot toMap → fromMap', () {
      final b = BlockedSlot.fromMap(_block(tables: [1, 2], sport: 'tenis'));
      final back = BlockedSlot.fromMap(b.toMap());
      expect(back.tableIds, [1, 2]);
      expect(back.sport, 'tenis');
      expect(back.allTables, isFalse);
    });
  });

  group('VenueTools.moveConflict - conflicte de rezervări', () {
    final moving = _match('m1', 1, 18, 19);

    test('masă liberă: se poate muta', () {
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [moving]),
        isNull,
      );
    });

    test('suprapunere pe aceeași masă = conflict', () {
      final other = _match('m2', 2, 18.5, 19.5);
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [moving, other]),
        'conflict',
      );
    });

    test('rezervări una după alta nu intră în conflict', () {
      final other = _match('m2', 2, 19, 20);
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [other]),
        isNull,
      );
    });

    test('altă masă: fără conflict', () {
      final other = _match('m2', 3, 18, 19);
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [other]),
        isNull,
      );
    });

    test('rezervarea anulată nu blochează masa', () {
      final other = _match('m2', 2, 18, 19, status: 'cancelled');
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [other]),
        isNull,
      );
    });

    test('alt sport, aceeași masă: fără conflict', () {
      final other = _match('m2', 2, 18, 19, sport: 'tenis');
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: null, dayMatches: [other]),
        isNull,
      );
    });

    test('rezervarea nu intră în conflict cu ea însăși', () {
      expect(
        VenueTools.moveConflict(match: moving, newTableId: 1, newStart: 18.5, newEnd: 19.5, venueData: null, dayMatches: [moving]),
        isNull,
      );
    });

    test('interval blocat de sală = blocked', () {
      final v = {'blockedSlots': [_block(start: 18, end: 20, tables: [2])]};
      expect(VenueTools.moveConflict(match: moving, newTableId: 2, newStart: 18, newEnd: 19, venueData: v), 'blocked');
      // altă masă nu e blocată
      expect(VenueTools.moveConflict(match: moving, newTableId: 3, newStart: 18, newEnd: 19, venueData: v), isNull);
    });

    test('blocarea pe toate mesele oprește orice mutare', () {
      final v = {'blockedSlots': [_block(start: 18, end: 20)]};
      expect(VenueTools.moveConflict(match: moving, newTableId: 5, newStart: 19, newEnd: 20, venueData: v), 'blocked');
    });
  });

  group('VenueTools.tablesFor / sports', () {
    test('sport implicit', () {
      expect(VenueTools.sports(null), ['ping_pong']);
      expect(VenueTools.sports({'supportedSports': <String>[]}), ['ping_pong']);
      expect(VenueTools.sports({'supportedSports': ['tenis', 'fotbal']}), ['tenis', 'fotbal']);
    });

    test('fără plan: 4 mese interioare implicit', () {
      final t = VenueTools.tablesFor(const {}, 'ping_pong');
      expect(t.map((e) => e['tableId']), [1, 2, 3, 4]);
    });

    test('numărul de resurse pe sport (interior + exterior)', () {
      final v = {
        'resourcesPerSport': {
          'tenis': {'indoor': 2, 'outdoor': 1},
        },
      };
      final t = VenueTools.tablesFor(v, 'tenis');
      expect(t.length, 3);
      expect(t.last['type'], 'outdoor');
    });

    test('planul sălii are prioritate și se sortează după id', () {
      final v = {
        'layouts': {
          'ping_pong': [
            {'tableId': 12, 'name': 'B', 'type': 'indoor'},
            {'tableId': 10, 'name': 'A', 'type': 'indoor'},
          ],
        },
      };
      expect(VenueTools.tablesFor(v, 'ping_pong').map((e) => e['tableId']), [10, 12]);
      expect(VenueTools.tablesFor(v, 'tenis'), isEmpty);
    });

    test('date lipsă', () {
      expect(VenueTools.tablesFor(null, 'ping_pong'), isEmpty);
    });
  });
}
