import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/level_utils.dart';

void main() {
  group('LevelUtils.getHourlyPrice Tests', () {
    test('Parsea corect formatul românesc original cu "de lei" și ordine inversă ("dupa 17 40")', () {
      const priceText = "30 de lei inainte de 17 si dupa 17 40";
      
      // Orele înainte de 17:00
      expect(LevelUtils.getHourlyPrice(priceText, 15), 30.0);
      expect(LevelUtils.getHourlyPrice(priceText, 16), 30.0);
      
      // Orele după sau egale cu 17:00
      expect(LevelUtils.getHourlyPrice(priceText, 17), 40.0);
      expect(LevelUtils.getHourlyPrice(priceText, 18), 40.0);
    });

    test('Calculează corect prețul total pentru rezervarea orele 16, 17, 18 (16:00 - 19:00)', () {
      const priceText = "30 de lei inainte de 17 si dupa 17 40";
      
      // Rezervarea de la 16:00 la 19:00 cuprinde 3 ore:
      // - 16:00 - 17:00 (ora 16) -> 30 lei
      // - 17:00 - 18:00 (ora 17) -> 40 lei
      // - 18:00 - 19:00 (ora 18) -> 40 lei
      // Total: 30 + 40 + 40 = 110 lei
      final total = LevelUtils.calculateTotalBookingPrice(priceText, 16, 19);
      expect(total, 110.0);
    });

    test('Parsea corect alte variații de format', () {
      // Variație cu "de lei" și ordine standard
      const text1 = "30 de lei inainte de 17 si 40 de lei dupa 17";
      expect(LevelUtils.getHourlyPrice(text1, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text1, 17), 40.0);

      // Variație cu "de la"
      const text2 = "30 lei pana la 17, 40 lei de la 17";
      expect(LevelUtils.getHourlyPrice(text2, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text2, 17), 40.0);

      // Ordine complet inversă: "inainte de 17 30, dupa 17 40"
      const text3 = "inainte de 17 30, dupa 17 40";
      expect(LevelUtils.getHourlyPrice(text3, 16), 30.0);
      expect(LevelUtils.getHourlyPrice(text3, 17), 40.0);
    });
  });
}
