/// Turns a typed phone number into the international digits WhatsApp needs, or null if it is not
/// a valid number. Bangladesh mobile numbers (01XXXXXXXXX, +8801XXXXXXXXX, 8801XXXXXXXXX,
/// 1XXXXXXXXX) become 8801XXXXXXXXX. A number starting with "+" from another country is
/// accepted when it has 8 to 15 digits.
String? normalizeBdPhone(String input) {
  final trimmed = input.trim();
  final hadPlus = trimmed.startsWith('+');
  // Keep only digits. English, Bengali and Hindi digits all become 0-9. Everything else is dropped.
  final buffer = StringBuffer();
  for (final rune in trimmed.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0x09E6 && rune <= 0x09EF) {
      buffer.writeCharCode(0x30 + rune - 0x09E6);
    } else if (rune >= 0x0966 && rune <= 0x096F) {
      buffer.writeCharCode(0x30 + rune - 0x0966);
    }
  }
  var digits = buffer.toString();
  if (digits.isEmpty) {
    return null;
  }
  if (digits.startsWith('00880')) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0') && digits.length == 11) {
    digits = '880${digits.substring(1)}';
  } else if (digits.length == 10 && digits.startsWith('1')) {
    digits = '880$digits';
  }
  // Bangladesh mobile: 880 1 [3-9] and 8 more digits (13 digits in all).
  if (digits.length == 13 && digits.startsWith('8801')) {
    final operator = digits.codeUnitAt(4) - 0x30;
    if (operator >= 3 && operator <= 9) {
      return digits;
    }
  }
  if (hadPlus && !digits.startsWith('880') && digits.length >= 8 && digits.length <= 15) {
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
