import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/hour_utils.dart';

void main() {
  group('hourValue', () {
    test('citește int și double din Firestore', () {
      expect(hourValue(17), 17.0);
      expect(hourValue(17.5), 17.5);
    });

    test('folosește fallback pentru null / tip greșit', () {
      expect(hourValue(null), 0.0);
      expect(hourValue('17'), 0.0);
      expect(hourValue(null, 10), 10.0);
    });
  });

  group('formatHour', () {
    test('ore întregi și jumătăți', () {
      expect(formatHour(9), '09:00');
      expect(formatHour(17.0), '17:00');
      expect(formatHour(17.5), '17:30');
    });

    test('valoare lipsă', () {
      expect(formatHour(null), '?');
    });
  });

  group('dateAtHour', () {
    test('ora întreagă', () {
      expect(dateAtHour('2026-10-12', 18), DateTime(2026, 10, 12, 18, 0));
    });

    test('jumătate de oră (double din Firestore)', () {
      expect(dateAtHour('2026-10-12', 17.5), DateTime(2026, 10, 12, 17, 30));
    });

    test('dată invalidă aruncă FormatException', () {
      expect(() => dateAtHour('2026/10/12', 18), throwsFormatException);
    });
  });
}
