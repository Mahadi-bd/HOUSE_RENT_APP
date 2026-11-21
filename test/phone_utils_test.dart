import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/utils/phone_utils.dart';

void main() {
  group('normalizeBdPhone', () {
    test('Bangladesh formats all become 8801XXXXXXXXX', () {
      for (final input in [
        '01711111111',
        '+8801711111111',
        '8801711111111',
        '1711111111',
        '017 1111-1111',
        '+880 1711 111111',
        '008801711111111',
        '০১৭১১১১১১১১',
      ]) {
        expect(normalizeBdPhone(input), '8801711111111', reason: input);
      }
    });

    test('invalid Bangladesh numbers are refused', () {
      for (final input in ['', 'abc', '0171111111', '01211111111', '02-9999999', '12345']) {
        expect(normalizeBdPhone(input), isNull, reason: input);
      }
    });

    test('a foreign number is accepted only with a plus sign', () {
      expect(normalizeBdPhone('+14155550123'), '14155550123');
      expect(normalizeBdPhone('14155550123'), isNull);
    });
  });

  group('whatsAppUri', () {
    test('with a number: wa.me/<number>?text=<encoded>', () {
      final uri = whatsAppUri('01711111111', 'Receipt R1 for Nov & more');
      expect(uri.toString(), startsWith('https://wa.me/8801711111111?text='));
      expect(uri.queryParameters['text'], 'Receipt R1 for Nov & more');
      expect(uri.toString(), isNot(contains(' ')));
    });

    test('without a valid number the person chooses the contact', () {
      expect(whatsAppUri(null, 'hi').toString(), startsWith('https://wa.me/?text='));
      expect(whatsAppUri('bad', 'hi').toString(), startsWith('https://wa.me/?text='));
    });

    test('Bengali text survives encoding', () {
      final uri = whatsAppUri('01711111111', 'ধন্যবাদ ৳১০,০০০');
      expect(uri.queryParameters['text'], 'ধন্যবাদ ৳১০,০০০');
    });
  });
}
