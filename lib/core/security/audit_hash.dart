import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Previous-hash value of the first record in an organization's audit chain.
final String auditGenesisHash = '0' * 64;

/// The exact text that is hashed for one audit record. The field order never changes.
String auditPayload({
  required String id,
  required String orgId,
  required String userId,
  required String action,
  required String entityType,
  required String entityId,
  required String? oldValue,
  required String? newValue,
  required int timestampSeconds,
}) {
  return jsonEncode([
    id,
    orgId,
    userId,
    action,
    entityType,
    entityId,
    oldValue,
    newValue,
    timestampSeconds,
  ]);
}

/// SHA-256 of (previous hash + payload), as lowercase hex.
String computeAuditHash({required String prevHash, required String payload}) {
  return sha256.convert(utf8.encode(prevHash + payload)).toString();
}
