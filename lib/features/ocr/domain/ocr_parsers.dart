import 'package:rent_solution/core/utils/id_numbers.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/enums.dart';

/// Things the NID reader could not find. The person must fill them in by hand.
enum NidWarning { noNidNumber, noDateOfBirth, noName }

/// What was read from a National ID card photo. Every value is a SUGGESTION: a person must
/// check it against the card before anything is saved.
class NidScan {
  /// Creates a scan result.
  const NidScan({
    this.nidNo,
    this.name,
    this.fatherName,
    this.motherName,
    this.dateOfBirth,
    this.warnings = const [],
  });

  /// NID number (10, 13 or 17 digits) or null.
  final String? nidNo;

  /// Name as printed (English or Bengali).
  final String? name;

  /// Father's name.
  final String? fatherName;

  /// Mother's name.
  final String? motherName;

  /// Date of birth (UTC midnight).
  final DateTime? dateOfBirth;

  /// What is missing.
  final List<NidWarning> warnings;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

String? _labelValue(List<String> lines, RegExp label) {
  for (final line in lines) {
    final m = label.firstMatch(line);
    if (m != null) {
      final value = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.length >= 2) {
        return value;
      }
    }
  }
  return null;
}

DateTime? _parseDate(String text) {
  final named = RegExp(r'(\d{1,2})[\s\-/,.]+([A-Za-z]{3,9})[\s\-/,.]+(\d{4})').firstMatch(text);
  if (named != null) {
    final month = _months[named.group(2)!.toLowerCase().substring(0, 3)];
    final day = int.parse(named.group(1)!);
    final year = int.parse(named.group(3)!);
    if (month != null && _valid(year, month, day)) {
      return DateTime.utc(year, month, day);
    }
  }
  final numeric = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(text);
  if (numeric != null) {
    final day = int.parse(numeric.group(1)!);
    final month = int.parse(numeric.group(2)!);
    final year = int.parse(numeric.group(3)!);
    if (_valid(year, month, day)) {
      return DateTime.utc(year, month, day);
    }
  }
  return null;
}

bool _valid(int year, int month, int day) {
  if (year < 1900 || year > DateTime.now().year || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  final d = DateTime.utc(year, month, day);
  return d.month == month && d.day == day;
}

/// Reads fields from OCR text of a Bangladesh National ID card (English and Bengali labels).
NidScan parseNidText(String raw) {
  final text = toEnglishDigits(raw);
  final lines = [for (final l in text.split(RegExp(r'[\r\n]+'))) if (l.trim().isNotEmpty) l.trim()];

  String? nid;
  final labelled = RegExp(r'I\.?D\.?\s*(?:NO|N0|NUMBER)?\s*[:.\-]?\s*((?:\d[ \-]?){10,17})', caseSensitive: false)
      .firstMatch(text);
  if (labelled != null) {
    nid = normalizeNid(labelled.group(1)!);
  }
  if (nid == null) {
    for (final m in RegExp(r'(?:\d[ \-]?){10,17}').allMatches(text)) {
      nid = normalizeNid(m.group(0)!);
      if (nid != null) {
        break;
      }
    }
  }

  DateTime? dob;
  for (final line in lines) {
    if (RegExp(r'birth|জন্ম', caseSensitive: false).hasMatch(line)) {
      dob = _parseDate(line);
      if (dob != null) {
        break;
      }
    }
  }
  dob ??= _parseDate(text);

  final name = _labelValue(lines, RegExp(r'^\s*(?:Name|নাম)\s*[:ঃ\-]?\s*(.+)$', caseSensitive: false));
  final father = _labelValue(lines, RegExp(r'^\s*(?:Father|পিতা)\s*[:ঃ\-]?\s*(.+)$', caseSensitive: false));
  final mother = _labelValue(lines, RegExp(r'^\s*(?:Mother|মাতা)\s*[:ঃ\-]?\s*(.+)$', caseSensitive: false));

  return NidScan(
    nidNo: nid,
    name: name,
    fatherName: father,
    motherName: mother,
    dateOfBirth: dob,
    warnings: [
      if (nid == null) NidWarning.noNidNumber,
      if (dob == null) NidWarning.noDateOfBirth,
      if (name == null) NidWarning.noName,
    ],
  );
}

/// What was read from a bKash, Nagad or Rocket screenshot. Suggestions only.
class MobileMoneyScan {
  /// Creates a result.
  const MobileMoneyScan({this.method, this.trxId, this.amountPoisha});

  /// The provider, if recognised.
  final PaymentMethod? method;

  /// The transaction ID, if found.
  final String? trxId;

  /// The amount in poisha, if found.
  final int? amountPoisha;
}

/// Reads provider, transaction ID and amount from OCR text of a mobile-money screenshot.
MobileMoneyScan parseMobileMoneyText(String raw) {
  final text = toEnglishDigits(raw);
  PaymentMethod? method;
  final lower = text.toLowerCase();
  if (lower.contains('bkash') || text.contains('বিকাশ')) {
    method = PaymentMethod.bkash;
  } else if (lower.contains('nagad') || text.contains('নগদ')) {
    method = PaymentMethod.nagad;
  } else if (lower.contains('rocket') || text.contains('রকেট')) {
    method = PaymentMethod.rocket;
  }
  final trx = RegExp(r'(?:Trx\s*ID|Transaction\s*ID|TxnID)\s*[:#\-]?\s*([A-Za-z0-9]{8,12})', caseSensitive: false)
      .firstMatch(text)
      ?.group(1)
      ?.toUpperCase();
  int? amount;
  final money = RegExp(r'(?:Tk\.?|BDT|৳)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(text);
  if (money != null) {
    amount = parseTakaToPoisha(money.group(1)!);
  }
  return MobileMoneyScan(method: method, trxId: trx, amountPoisha: amount);
}
