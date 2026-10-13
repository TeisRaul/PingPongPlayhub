import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/services/checkin_service.dart';

void main() {
  group('CheckInService.parseCode', () {
    test('taie spațiile', () => expect(CheckInService.parseCode('  abc123 \n'), 'abc123'));
    test('cod gol', () => expect(CheckInService.parseCode('   '), ''));
    test('respinge căi cu slash', () => expect(CheckInService.parseCode('matches/abc'), ''));
  });

  group('CheckInService cod scurt', () {
    test('valori fixe (același cod pe orice platformă)', () {
      expect(CheckInService.shortCode('abc'), 'AV5T7D');
      expect(CheckInService.shortCode('ZTuK3p0wMqXr8vYhE2dL'), 'D3ZWMA');
      expect(CheckInService.shortCode('matchId1'), 'PC97E7');
    });

    test('are 6 caractere din alfabetul fără ambiguități', () {
      final code = CheckInService.shortCode('orice-id-de-meci');
      expect(code.length, 6);
      expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$').hasMatch(code), isTrue);
    });

    test('formatare cu cratimă', () {
      expect(CheckInService.formatShortCode('AV5T7D'), 'AV5-T7D');
    });

    test('normalizare: majuscule, spații și cratimă', () {
      expect(CheckInService.normalizeShortCode(' av5-t7d '), 'AV5T7D');
      expect(CheckInService.normalizeShortCode('AV5 T7D'), 'AV5T7D');
    });

    test('respinge ce nu e cod scurt', () {
      expect(CheckInService.normalizeShortCode('ABC'), isNull);
      expect(CheckInService.normalizeShortCode('AV5T7O'), isNull); // O nu există în alfabet
      expect(CheckInService.normalizeShortCode('ZTuK3p0wMqXr8vYhE2dL'), isNull);
    });
  });

  group('CheckInService.messageFor', () {
    test('toate statusurile au mesaj', () {
      for (final s in CheckInStatus.values) {
        expect(CheckInService.messageFor(s, {'date': '2026-10-13'}), isNotEmpty);
      }
    });

    test('ended include ora de final', () {
      expect(CheckInService.messageFor(CheckInStatus.ended, {'endHour': 21.5}), contains('21:30'));
    });

    test('notToday include data meciului', () {
      expect(CheckInService.messageFor(CheckInStatus.notToday, {'date': '2026-10-14'}),
          contains('2026-10-14'));
    });
  });

  group('CheckInLookup.tableLikelyBusy', () {
    test('liberă fără suprapuneri', () {
      expect(const CheckInLookup(CheckInStatus.ok).tableLikelyBusy, isFalse);
    });

    test('suprapunere fără check-in nu blochează', () {
      final l = CheckInLookup(CheckInStatus.ok, overlaps: [{'checkedIn': false}]);
      expect(l.tableLikelyBusy, isFalse);
    });

    test('suprapunere cu check-in = ocupată', () {
      final l = CheckInLookup(CheckInStatus.ok, overlaps: [{'checkedIn': true}]);
      expect(l.tableLikelyBusy, isTrue);
    });
  });
}
