/// Turns Bengali or Hindi digits into English digits.
String toEnglishDigits(String input) {
  const bengali = '০১২৩৪৫৬৭৮৯';
  const hindi = '०१२३४५६७८९';
  var out = input;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(bengali[i], '$i').replaceAll(hindi[i], '$i');
  }
  return out;
}

/// A Bangladesh National ID number: 10, 13 or 17 digits (spaces and dashes allowed).
/// Returns the digits only, or null when it is not valid.
String? normalizeNid(String input) {
  final digits = toEnglishDigits(input).replaceAll(RegExp(r'[\s\-]'), '');
  return RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(digits) ? digits : null;
}

/// Another identity number (birth registration, passport, driving licence): 6 to 20 letters
/// or digits. Returns it upper-cased without spaces, or null.
String? normalizeOtherId(String input) {
  final id = toEnglishDigits(input).replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  return RegExp(r'^[A-Z0-9]{6,20}$').hasMatch(id) ? id : null;
}
