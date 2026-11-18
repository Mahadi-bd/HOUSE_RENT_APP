import 'package:intl/intl.dart';

/// Locale-aware money, number and date text. Money is kept as integer poisha (1 BDT = 100).
class AppFormatters {
  /// Creates formatters for [languageCode] (en, bn or hi).
  AppFormatters(this.languageCode);

  /// The app language code.
  final String languageCode;

  /// The intl locale that gives lakh/crore grouping and the right digits.
  String get _locale {
    switch (languageCode) {
      case 'bn':
        return 'bn_BD';
      case 'hi':
        return 'hi_IN';
      default:
        return 'en_IN';
    }
  }

  /// Taka amount with the ৳ symbol. Shows poisha only when there are any.
  String money(int poisha) {
    final negative = poisha < 0;
    final abs = poisha.abs();
    final taka = abs ~/ 100;
    final rest = abs % 100;
    final whole = NumberFormat.decimalPattern(_locale).format(taka);
    final fraction = rest == 0 ? '' : '.${NumberFormat('00', _locale).format(rest)}';
    return '${negative ? '-' : ''}৳$whole$fraction';
  }

  /// Same as [money] but with "BDT " instead of the taka sign, for PDFs that use a font
  /// without that sign.
  String moneyCode(int poisha) => money(poisha).replaceFirst('৳', 'BDT ').replaceFirst('-BDT ', 'BDT -');

  /// A plain whole number with local digits and grouping.
  String number(int value) => NumberFormat.decimalPattern(_locale).format(value);

  /// A date such as "10 Nov 2026" in the app language.
  String date(DateTime value) => DateFormat.yMMMd(_locale).format(value);

  /// A month label from "2026-11", such as "November 2026" in the app language.
  String monthLabel(String yyyyMm) {
    final parts = yyyyMm.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return DateFormat.yMMMM(_locale).format(DateTime(year, month));
  }
}
