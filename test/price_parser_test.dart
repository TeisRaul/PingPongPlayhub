import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/level_utils.dart';

void main() {
  group('LevelUtils.getHourlyPrice - formate românești', () {
    // ── Format 1: "30 de lei inainte de 17 si dupa 17 40" ──────────────────
    test('Format clasic: preț + keyword + oră (fără diacritice)', () {
      const text = '30 de lei inainte de 17 si dupa 17 40';
      expect(LevelUtils.getHourlyPrice(text, 15), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 17), 40.0);
      expect(LevelUtils.getHourlyPrice(text, 18), 40.0);
    });

    // ── Format 2: hint-ul exact din aplicație ──────────────────────────────
    test('Hint exact din aplicație: "30 RON/oră înainte de 17:00, 40 RON/oră după 17:00"', () {
      const text = '30 RON/oră înainte de 17:00, 40 RON/oră după 17:00';
      expect(LevelUtils.getHourlyPrice(text, 15), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 17), 40.0);
      expect(LevelUtils.getHourlyPrice(text, 18), 40.0);
    });

    // ── Format 3: fără diacritice pe "oră" ────────────────────────────────
    test('Format fără diacritice: "30 RON/ora inainte de 17:00, 40 RON/ora dupa 17:00"', () {
      const text = '30 RON/ora inainte de 17:00, 40 RON/ora dupa 17:00';
      expect(LevelUtils.getHourlyPrice(text, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 17), 40.0);
    });

    // ── Format 4: ordine inversă (keyword + oră + preț) ───────────────────
    test('Ordine inversă: "inainte de 17 30, dupa 17 40"', () {
      const text = 'inainte de 17 30, dupa 17 40';
      expect(LevelUtils.getHourlyPrice(text, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 17), 40.0);
    });

    // ── Format 5: "pana la / de la" ───────────────────────────────────────
    test('Format cu pana la / de la: "30 lei pana la 17, 40 lei de la 17"', () {
      const text = '30 lei pana la 17, 40 lei de la 17';
      expect(LevelUtils.getHourlyPrice(text, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text, 17), 40.0);
    });

    // ── Format 6: tarif fix ────────────────────────────────────────────────
    test('Tarif fix: "25 RON/oră"', () {
      expect(LevelUtils.getHourlyPrice('25 RON/oră', 14), 25.0);
      expect(LevelUtils.getHourlyPrice('25 RON/oră', 20), 25.0);
    });
  });

  group('LevelUtils.calculateTotalBookingPrice - calcul total', () {
    // Orele 16, 17, 18 → 30 + 40 + 40 = 110
    test('Total: 30 înainte de 17 și 40 după 17, rezervare 16:00-19:00 = 110 lei', () {
      const text = '30 de lei inainte de 17 si dupa 17 40';
      expect(LevelUtils.calculateTotalBookingPrice(text, 16, 19), 110.0);
    });

    // Același test cu format hint
    test('Total cu hint format exact: rezervare 16:00-19:00 = 110 lei', () {
      const text = '30 RON/oră înainte de 17:00, 40 RON/oră după 17:00';
      expect(LevelUtils.calculateTotalBookingPrice(text, 16, 19), 110.0);
    });

    // startHour == endHour → 0
    test('startHour == endHour → 0 lei', () {
      expect(LevelUtils.calculateTotalBookingPrice('30 RON/oră', 16, 16), 0.0);
    });

    // Tarif fix: 3 ore × 25 = 75
    test('Tarif fix 25 RON, 3 ore → 75 lei', () {
      expect(LevelUtils.calculateTotalBookingPrice('25 RON/oră', 14, 17), 75.0);
    });
  });
}
