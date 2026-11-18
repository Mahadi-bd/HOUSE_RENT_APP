/// Turns what a person typed (for example "1,200.50" or Bengali digits) into poisha.
/// Returns null when the text is not a valid amount, or is zero and [allowZero] is false.
int? parseTakaToPoisha(String input, {bool allowZero = false}) {
  var text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  const bengali = '০১২৩৪৫৬৭৮৯';
  const hindi = '०१२३४५६७८९';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(bengali[i], '$i').replaceAll(hindi[i], '$i');
  }
  text = text.replaceAll(',', '').replaceAll('৳', '').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) {
    return null;
  }
  final whole = int.parse(match.group(1)!);
  if (whole > 1000000000) {
    return null;
  }
  final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
  final poisha = whole * 100 + fraction;
  if (poisha == 0 && !allowZero) {
    return null;
  }
  return poisha;
}

/// Poisha as plain taka text for an input box, such as "1000" or "1000.50".
String poishaToPlainTaka(int poisha) {
  final whole = poisha ~/ 100;
  final rest = poisha % 100;
  return rest == 0 ? '$whole' : '$whole.${rest.toString().padLeft(2, '0')}';
}
