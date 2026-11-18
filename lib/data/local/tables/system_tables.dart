// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/enums.dart';

/// Append-only, hash-chained audit log. Triggers block UPDATE and DELETE; the hash chain
/// (see AuditDao) detects any change made by bypassing the triggers.
/// Never put vault data (NID, addresses) in old_value or new_value.
@TableIndex(name: 'idx_audit_org_seq', columns: {#orgId, #seq})
class AuditLogs extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get orgId => text()();
  TextColumn get userId => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get prevHash => text()();
  TextColumn get currHash => text()();
  // Stored with whole-second precision; the hash uses the same seconds value.
  DateTimeColumn get timestamp => dateTime()();
}

/// Encrypted operation records waiting to be sent (outbox) or applied (inbox).
@TableIndex(name: 'idx_sync_ops_state', columns: {#orgId, #state})
@TableIndex(name: 'idx_sync_ops_order', columns: {#orgId, #direction, #hlc})
class SyncOps extends Table {
  // Operation id (random UUID), same value as the relay document id.
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get deviceId => text()();
  TextColumn get senderUid => text()();
  // Packed hybrid logical clock (see Hlc.pack).
  TextColumn get hlc => text()();
  TextColumn get channel => textEnum<SyncChannel>()();
  TextColumn get direction => textEnum<SyncDirection>()();
  IntColumn get keyVersion => integer()();
  TextColumn get nonce => text()();
  TextColumn get ciphertext => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expireAt => dateTime()();
  TextColumn get state =>
      textEnum<SyncOpState>().withDefault(Constant(SyncOpState.pending.name))();
  DateTimeColumn get appliedAt => dateTime().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  TextColumn get rejectReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
