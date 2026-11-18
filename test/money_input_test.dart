import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/domain/money/ledger.dart';
import 'package:rent_solution/domain/money/rent_charges.dart';

void main() {
  group('parseTakaToPoisha', () {
    test('plain, grouped and decimal amounts', () {
      expect(parseTakaToPoisha('1200'), 120000);
      expect(parseTakaToPoisha('1,200.5'), 120050);
      expect(parseTakaToPoisha('৳ 12,000.25'), 1200025);
      expect(parseTakaToPoisha('0.05'), 5);
    });

    test('Bengali and Hindi digits', () {
      expect(parseTakaToPoisha('১২০০'), 120000);
      expect(parseTakaToPoisha('१२००.५०'), 120050);
    });

    test('rejects bad input', () {
      for (final bad in ['', ' ', 'abc', '-5', '12.345', '1.2.3', '1e5', '0', '0.00', '99999999999']) {
        expect(parseTakaToPoisha(bad), isNull, reason: bad);
      }
      expect(parseTakaToPoisha('0', allowZero: true), 0);
    });

    test('plain text for input boxes round-trips', () {
      expect(poishaToPlainTaka(100000), '1000');
      expect(poishaToPlainTaka(100050), '1000.50');
      expect(parseTakaToPoisha(poishaToPlainTaka(123405)), 123405);
    });
  });

  group('mergeExtraCharges', () {
    test('extras add to the same month; extra-only months appear', () {
      final merged = mergeExtraCharges(
        const [MonthCharge('2026-09', 1000000), MonthCharge('2026-10', 1000000)],
        [
          (month: '2026-10', amount: 50000),
          (month: '2026-10', amount: 25000),
          (month: '2026-12', amount: 10000),
        ],
      );
      expect(merged.map((c) => c.month), ['2026-09', '2026-10', '2026-12']);
      expect(merged.map((c) => c.amount), [1000000, 1075000, 10000]);
    });

    test('no extras changes nothing; negative extras are rejected', () {
      const base = [MonthCharge('2026-09', 5)];
      expect(mergeExtraCharges(base, const []).single.amount, 5);
      expect(() => mergeExtraCharges(base, [(month: '2026-09', amount: -1)]), throwsArgumentError);
    });
  });
}
