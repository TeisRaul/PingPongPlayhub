import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/l10n/strings.dart';
import 'package:pingpong_playhub/services/voucher_service.dart';

void main() {
  group('VoucherResult.validFor', () {
    test('valabil doar pentru prețul pentru care s-a calculat', () {
      const r = VoucherResult(ok: true, discount: 10, amount: 80);
      expect(r.validFor(80), isTrue);
      expect(r.validFor(80.004), isTrue);
      expect(r.validFor(60), isFalse); // s-a schimbat masa / ora
    });

    test('un cod respins nu e valabil niciodată', () {
      const r = VoucherResult(ok: false, reason: 'expired', amount: 80);
      expect(r.validFor(80), isFalse);
    });
  });

  group('VoucherResult.errorMessage', () {
    test('toate motivele cunoscute au text propriu', () {
      for (final reason in [
        'not_found',
        'inactive',
        'expired',
        'not_started',
        'exhausted',
        'already_used',
        'not_new_user',
        'too_many_attempts',
      ]) {
        final msg = VoucherResult(ok: false, reason: reason).errorMessage;
        expect(msg, isNot('vc.err_$reason'), reason: 'lipsește traducerea pentru $reason');
        expect(msg, isNotEmpty);
      }
    });

    test('suma minimă apare în mesaj', () {
      final msg = const VoucherResult(ok: false, reason: 'min_amount', minAmount: 50).errorMessage;
      expect(msg, contains('50'));
    });

    test('motiv necunoscut: mesajul generic', () {
      expect(const VoucherResult(ok: false, reason: 'ceva_nou').errorMessage, tr('vc.err_unavailable'));
      expect(const VoucherResult(ok: false).errorMessage, tr('vc.err_unavailable'));
    });
  });
}
