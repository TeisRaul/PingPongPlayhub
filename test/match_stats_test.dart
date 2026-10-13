import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/utils/match_stats.dart';

void main() {
  group('didUserWinMatch', () {
    test('1v1: câștigătorul din winnerUid', () {
      expect(didUserWinMatch({'winnerUid': 'a'}, 'a'), isTrue);
      expect(didUserWinMatch({'winnerUid': 'a'}, 'b'), isFalse);
    });

    test('2v2: câștigătorii din winnerUids', () {
      final m = {'winnerUids': ['a', 'b']};
      expect(didUserWinMatch(m, 'b'), isTrue);
      expect(didUserWinMatch(m, 'c'), isFalse);
    });

    test('meci egal sau fără câștigător', () {
      expect(didUserWinMatch({}, 'a'), isFalse);
      expect(didUserWinMatch({'winnerUids': null}, 'a'), isFalse);
    });
  });

  group('formatWinRate', () {
    test('fără meciuri', () => expect(formatWinRate(0, 0), '0%'));
    test('procent întreg', () => expect(formatWinRate(3, 5), '60%'));
    test('procent zecimal', () => expect(formatWinRate(1, 3), '33.3%'));
  });
}
