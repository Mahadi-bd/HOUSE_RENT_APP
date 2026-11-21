/// Turns a typed phone number into the international digits WhatsApp needs, or null if it is not
/// a valid number. Bangladesh mobile numbers (01XXXXXXXXX, +8801XXXXXXXXX, 8801XXXXXXXXX,
/// 1XXXXXXXXX) become 8801XXXXXXXXX. A number starting with "+" from another country is
/// accepted when it has 8 to 15 digits.
String? normalizeBdPhone(String input) {
  final trimmed = input.trim();
  final hadPlus = trimmed.startsWith('+');
  const bengali = '০১২৩৪৫৬৭৮৯';
  var digits = trimmed;
  for (var i = 0; i < 10; i++) {
    digits = digits.replaceAll(bengali[i], '$i');
  }
  digits = digits.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }

  // Bangladesh's international form is +880 followed by a 10-digit mobile number.
  // Accept 00-prefixed international dialing and common local forms as well.
  if (digits.startsWith('00')) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('8801') && RegExp(r'^8801[3-9]\d{8}$').hasMatch(digits)) {
    return digits;
  }
  if (digits.startsWith('01') && RegExp(r'^01[3-9]\d{8}$').hasMatch(digits)) {
    return '88${digits.substring(1)}';
  }
  if (digits.length == 10 && RegExp(r'^1[3-9]\d{8}$').hasMatch(digits)) {
    return '880$digits';
  }
  if (hadPlus && !digits.startsWith('880') && RegExp(r'^\d{8,15}$').hasMatch(digits)) {
    return digits;
  }
  return null;
}

/// A WhatsApp chat link with [text] prefilled. Without a valid [phone] the person picks the
/// contact themselves. The person always taps Send; nothing is sent automatically.
Uri whatsAppUri(String? phone, String text) {
  final number = phone == null ? null : normalizeBdPhone(phone);
  return Uri.parse('https://wa.me/${number ?? ''}?text=${Uri.encodeQueryComponent(text)}');
}
