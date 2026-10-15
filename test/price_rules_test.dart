import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/level_utils.dart';
import 'package:pingpong_playhub/utils/price_rules.dart';

Map<String, dynamic> _rule({
  String id = 'r1',
  String mode = 'percent',
  List<int> days = const [],
  double start = 0,
  double end = 24,
  double value = 10,
  String? validFrom,
  String? validTo,
  bool active = true,
}) =>
    {
      'id': id,
      'name': id,
      'mode': mode,
      'days': days,
      'startHour': start,
      'endHour': end,
      'value': value,
      'validFrom': validFrom,
      'validTo': validTo,
      'active': active,
    };

void main() {
  // 19 oct 2026 = luni, 17 oct = sâmbătă, 18 oct = duminică
  final monday = DateTime(2026, 10, 19);
  final saturday = DateTime(2026, 10, 17);

  group('VenuePriceRule.matches', () {
    test('zilele săptămânii', () {
      final r = VenuePriceRule.fromMap(_rule(days: [1, 2, 3, 4, 5]));
      expect(r.matches(monday, 10), isTrue);
      expect(r.matches(saturday, 10), isFalse);
    });

    test('lista de zile goală = toate zilele', () {
      final r = VenuePriceRule.fromMap(_rule());
      expect(r.matches(monday, 10), isTrue);
      expect(r.matches(saturday, 10), isTrue);
    });

    test('intervalul orar: începutul inclus, sfârșitul exclus', () {
      final r = VenuePriceRule.fromMap(_rule(start: 9, end: 12));
      expect(r.matches(monday, 8.5), isFalse);
      expect(r.matches(monday, 9), isTrue);
      expect(r.matches(monday, 11.5), isTrue);
      expect(r.matches(monday, 12), isFalse);
    });

    test('perioada de valabilitate (capetele sunt incluse)', () {
      final r = VenuePriceRule.fromMap(_rule(validFrom: '2026-10-19', validTo: '2026-10-25'));
      expect(r.matches(DateTime(2026, 10, 18), 10), isFalse);
      expect(r.matches(DateTime(2026, 10, 19), 10), isTrue);
      expect(r.matches(DateTime(2026, 10, 25), 10), isTrue);
      expect(r.matches(DateTime(2026, 10, 26), 10), isFalse);
    });

    test('regula dezactivată nu se aplică', () {
      final r = VenuePriceRule.fromMap(_rule(active: false));
      expect(r.matches(monday, 10), isFalse);
    });
  });

  group('VenuePriceRule.applyToHalfHour', () {
    test('procent', () {
      expect(VenuePriceRule.fromMap(_rule(value: 25)).applyToHalfHour(20), closeTo(15, 1e-9));
    });
    test('procentul se limitează la 0-100', () {
      expect(VenuePriceRule.fromMap(_rule(value: 150)).applyToHalfHour(20), 0);
      expect(VenuePriceRule.fromMap(_rule(value: -10)).applyToHalfHour(20), 20);
    });
    test('tarif fix pe oră → jumătate pe jumătate de oră', () {
      expect(VenuePriceRule.fromMap(_rule(mode: 'fixed', value: 30)).applyToHalfHour(20), 15);
    });
  });

  group('VenuePriceRule.slotPrice / parseList', () {
    test('fără regulă sau fără dată: prețul de bază', () {
      expect(VenuePriceRule.slotPrice(const [], monday, 10, 20), 20);
      final rules = VenuePriceRule.parseList([_rule(value: 50)]);
      expect(VenuePriceRule.slotPrice(rules, null, 10, 20), 20);
    });

    test('prima regulă potrivită câștigă', () {
      final rules = VenuePriceRule.parseList([
        _rule(id: 'fix', mode: 'fixed', value: 30, start: 18, end: 22),
        _rule(id: 'pct', value: 50),
      ]);
      expect(VenuePriceRule.slotPrice(rules, monday, 18, 20), 15); // fixa
      expect(VenuePriceRule.slotPrice(rules, monday, 10, 20), 10); // procentul
    });

    test('parseList ignoră intrările stricate', () {
      final rules = VenuePriceRule.parseList([
        _rule(id: 'ok'),
        'nu e hartă',
        {
          'id': 'prost',
          'days': ['x'],
        },
        null,
      ]);
      expect(rules.map((r) => r.id), ['ok']);
      expect(VenuePriceRule.parseList(null), isEmpty);
      expect(VenuePriceRule.parseList('abc'), isEmpty);
    });

    test('toMap → fromMap păstrează regula', () {
      final r = VenuePriceRule.fromMap(_rule(mode: 'fixed', days: [6, 7], start: 10, end: 14, value: 25, validFrom: '2026-01-01'));
      final back = VenuePriceRule.fromMap(r.toMap());
      expect(back.mode, 'fixed');
      expect(back.days, [6, 7]);
      expect(back.startHour, 10);
      expect(back.endHour, 14);
      expect(back.value, 25);
      expect(back.validFrom, '2026-01-01');
      expect(back.validTo, isNull);
    });
  });

  group('LevelUtils.calculateVenueBookingPrice', () {
    final flat = <String, dynamic>{'priceType': 'flat', 'flatPriceHalf': 20.0};

    test('tarif fix: 2 ore = 4 jumătăți', () {
      expect(LevelUtils.calculateVenueBookingPrice(venueData: flat, startHour: 18, endHour: 20), 80);
    });

    test('jumătate de oră', () {
      expect(LevelUtils.calculateVenueBookingPrice(venueData: flat, startHour: 18, endHour: 18.5), 20);
      expect(LevelUtils.calculateVenueBookingPrice(venueData: flat, startHour: 18.5, endHour: 20), 60);
    });

    test('interval gol sau inversat costă 0', () {
      expect(LevelUtils.calculateVenueBookingPrice(venueData: flat, startHour: 18, endHour: 18), 0);
      expect(LevelUtils.calculateVenueBookingPrice(venueData: flat, startHour: 20, endHour: 18), 0);
    });

    test('tarif dinamic: înainte / după ora limită', () {
      final dyn = <String, dynamic>{
        'priceType': 'dynamic',
        'dynamicHourLimit': 17,
        'dynamicPriceHalfBefore': 15.0,
        'dynamicPriceHalfAfter': 20.0,
      };
      // 16:00-18:00 = 2 jumătăți la 15 + 2 la 20
      expect(LevelUtils.calculateVenueBookingPrice(venueData: dyn, startHour: 16, endHour: 18), 70);
      expect(LevelUtils.calculateVenueBookingPrice(venueData: dyn, startHour: 10, endHour: 11), 30);
      expect(LevelUtils.calculateVenueBookingPrice(venueData: dyn, startHour: 17, endHour: 18), 40);
    });

    test('valori implicite când sala nu are tarife salvate', () {
      expect(LevelUtils.calculateVenueBookingPrice(venueData: const {}, startHour: 10, endHour: 11), 30);
    });

    test('reducere procentuală doar pe o parte din rezervare', () {
      final venue = {
        ...flat,
        'priceRules': [_rule(days: [1, 2, 3, 4, 5], start: 9, end: 12, value: 25)],
      };
      // 11:00-13:00: 2 jumătăți reduse (15) + 2 normale (20)
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 11, endHour: 13, date: monday), 70);
      // sâmbăta regula nu se aplică
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 11, endHour: 13, date: saturday), 80);
      // fără dată, regulile se ignoră
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 11, endHour: 13), 80);
    });

    test('tarif fix pe interval (ex. 30 RON/oră seara)', () {
      final venue = {
        ...flat,
        'priceRules': [_rule(mode: 'fixed', value: 30, start: 18, end: 22)],
      };
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 18, endHour: 20, date: monday), 60);
    });

    test('regulă valabilă doar într-o perioadă', () {
      final venue = {
        ...flat,
        'priceRules': [_rule(value: 50, validFrom: '2026-11-01', validTo: '2026-11-30')],
      };
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 10, endHour: 11, date: monday), 40);
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 10, endHour: 11, date: DateTime(2026, 11, 2)), 20);
    });

    test('reducere 100% = gratuit', () {
      final venue = {
        ...flat,
        'priceRules': [_rule(value: 100)],
      };
      expect(LevelUtils.calculateVenueBookingPrice(venueData: venue, startHour: 10, endHour: 12, date: monday), 0);
    });
  });
}
