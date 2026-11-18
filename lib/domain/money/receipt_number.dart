import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:rent_solution/core/utils/date_utils.dart';

/// Four letters/digits that identify a device inside receipt numbers, so two phones that are
/// offline never create the same number.
String deviceCodeOf(String deviceId) =>
    sha256.convert(utf8.encode(deviceId)).toString().substring(0, 4).toUpperCase();

/// The start of every receipt number for [at] on [deviceId], like `R2611-9F3A-`.
String receiptPrefix(DateTime at, String deviceId) {
  final month = monthKeyOf(at);
  return 'R${month.substring(2, 4)}${month.substring(5, 7)}-${deviceCodeOf(deviceId)}-';
}

/// A full receipt number such as `R2611-9F3A-0007`.
String formatReceiptNo(String prefix, int sequence) =>
    '$prefix${sequence.toString().padLeft(4, '0')}';
