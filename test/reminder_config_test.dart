import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/reminder_config.dart';

void main() {
  final start = DateTime(2026, 10, 20, 18, 30);

  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  group('ReminderConfig.fromMap', () {
    test('fără date: valorile implicite (1 oră înainte, fără repetare)', () {
      final c = ReminderConfig.fromMap(null);
      expect(c.enabled, isTrue);
      expect(c.firstMin, 60);
      expect(c.repeats, isFalse);
    });

    test('valorile ilegale revin la implicit / se limitează', () {
      final c = ReminderConfig.fromMap({
        'firstMin': 45,
        'repeatEveryMin': 7,
        'repeatMode': 'altceva',
        'repeatCount': 99,
      });
      expect(c.firstMin, 60);
      expect(c.repeatEveryMin, 0);
      expect(c.untilStart, isFalse);
      expect(c.repeatCount, ReminderConfig.maxRepeatCount);
      expect(ReminderConfig.fromMap({'repeatCount': -4}).repeatCount, 0);
    });

    test('enabled=false se păstrează', () {
      expect(ReminderConfig.fromMap({'enabled': false}).enabled, isFalse);
    });

    test('toMap → fromMap păstrează setările', () {
      const c = ReminderConfig(firstMin: 1440, repeatEveryMin: 120, repeatMode: 'until_start', repeatCount: 3);
      final back = ReminderConfig.fromMap(c.toMap());
      expect(back.firstMin, 1440);
      expect(back.repeatEveryMin, 120);
      expect(back.untilStart, isTrue);
      expect(back.repeatCount, 3);
    });

    test('toate opțiunile din interfață sunt acceptate', () {
      for (final m in ReminderConfig.firstOptions) {
        expect(ReminderConfig.fromMap({'firstMin': m}).firstMin, m);
      }
      for (final m in ReminderConfig.repeatOptions) {
        expect(ReminderConfig.fromMap({'repeatEveryMin': m}).repeatEveryMin, m);
      }
    });
  });

  group('ReminderConfig.fireTimes', () {
    test('implicit: un singur reminder cu o oră înainte', () {
      final t = ReminderConfig.defaults.fireTimes(start);
      expect(t.map(hm), ['17:30']);
    });

    test('dezactivat: niciun reminder', () {
      expect(const ReminderConfig(enabled: false).fireTimes(start), isEmpty);
    });

    test('prima notificare cu 1 zi / 1 săptămână înainte', () {
      expect(const ReminderConfig(firstMin: 1440).fireTimes(start).single, DateTime(2026, 10, 19, 18, 30));
      expect(const ReminderConfig(firstMin: 10080).fireTimes(start).single, DateTime(2026, 10, 13, 18, 30));
    });

    test('repetare de un număr de ori', () {
      const c = ReminderConfig(firstMin: 1440, repeatEveryMin: 30, repeatMode: 'count', repeatCount: 2);
      final t = c.fireTimes(start);
      expect(t.length, 3);
      expect(t[1].difference(t[0]).inMinutes, 30);
      expect(t[2].difference(t[1]).inMinutes, 30);
    });

    test('repetările se opresc cu 10 minute înainte de meci', () {
      const c = ReminderConfig(firstMin: 180, repeatEveryMin: 60, repeatMode: 'count', repeatCount: 5);
      expect(c.fireTimes(start).map(hm), ['15:30', '16:30', '17:30']);
    });

    test('până începe meciul', () {
      const c = ReminderConfig(firstMin: 120, repeatEveryMin: 30, repeatMode: 'until_start');
      expect(c.fireTimes(start).map(hm), ['16:30', '17:00', '17:30', '18:00']);
    });

    test('maximum 20 de notificări', () {
      const c = ReminderConfig(firstMin: 10080, repeatEveryMin: 30, repeatMode: 'until_start');
      expect(c.fireTimes(start).length, 20);
    });

    test('prima notificare rămâne chiar dacă repetarea e mai lungă decât intervalul rămas', () {
      const c = ReminderConfig(firstMin: 60, repeatEveryMin: 1440, repeatMode: 'until_start');
      expect(c.fireTimes(start).length, 1);
    });
  });

  group('ReminderConfig.copyWith', () {
    test('schimbă doar ce i se cere', () {
      final c = ReminderConfig.defaults.copyWith(firstMin: 180, enabled: false);
      expect(c.firstMin, 180);
      expect(c.enabled, isFalse);
      expect(c.repeatEveryMin, ReminderConfig.defaults.repeatEveryMin);
    });
  });
}
