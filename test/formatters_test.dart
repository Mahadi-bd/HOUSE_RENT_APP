import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rent_solution/core/utils/formatters.dart';

void main() {
  setUpAll(initializeDateFormatting);

  group('BDT money (stored as poisha)', () {
    test('English uses lakh/crore grouping and the taka sign', () {
      expect(AppFormatters('en').money(123456700), '৳12,34,567');
      expect(AppFormatters('en').money(1250), '৳12.50');
      expect(AppFormatters('en').money(0), '৳0');
      expect(AppFormatters('en').money(-50000), '-৳500');
    });

    test('Bengali uses Bengali digits', () {
      final text = AppFormatters('bn').money(123456700);
      expect(text, contains('৳'));
      expect(text, contains('১২,৩৪,৫৬৭'));
    });

    test('Hindi shows the taka sign and grouping', () {
      final text = AppFormatters('hi').money(123456700);
      expect(text, startsWith('৳'));
      expect(text.length, greaterThan(5));
    });
  });

  group('dates and months', () {
    test('English', () {
      final f = AppFormatters('en');
      expect(f.date(DateTime(2026, 11, 10)), allOf(contains('Nov'), contains('2026')));
      expect(f.monthLabel('2026-11'), contains('November'));
    });

    test('Bengali month name and digits', () {
      final f = AppFormatters('bn');
      expect(f.date(DateTime(2026, 11, 10)), allOf(contains('নভেম্বর'), contains('২০২৬')));
      expect(f.monthLabel('2026-11'), contains('নভেম্বর'));
    });
  });
}
