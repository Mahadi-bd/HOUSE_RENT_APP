import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/domain/money/receipt_number.dart';

void main() {
  group('Bangladesh month (UTC+6)', () {
    test('late evening UTC on the last day is already next month in Bangladesh', () {
      expect(monthKeyOf(DateTime.utc(2026, 10, 31, 17, 59)), '2026-10');
      expect(monthKeyOf(DateTime.utc(2026, 10, 31, 18)), '2026-11');
    });

    test('year change', () {
      expect(monthKeyOf(DateTime.utc(2026, 12, 31, 18)), '2027-01');
      expect(nextMonthKey('2026-12'), '2027-01');
      expect(nextMonthKey('2026-01'), '2026-02');
    });

    test('monthsThrough is inclusive and empty when reversed', () {
      expect(monthsThrough('2026-11', '2027-02'), ['2026-11', '2026-12', '2027-01', '2027-02']);
      expect(monthsThrough('2027-01', '2026-12'), isEmpty);
    });
  });

  group('receipt numbers', () {
    test('format: R + yyMM + device code + 4-digit sequence', () {
      final prefix = receiptPrefix(DateTime.utc(2026, 11, 10), 'device-1');
      expect(prefix, matches(RegExp(r'^R2611-[0-9A-F]{4}-$')));
      expect(formatReceiptNo(prefix, 7), '${prefix}0007');
    });

    test('different devices get different codes; the same device is stable', () {
      expect(deviceCodeOf('device-1'), deviceCodeOf('device-1'));
      expect(deviceCodeOf('device-1'), isNot(deviceCodeOf('device-2')));
    });
  });
}
