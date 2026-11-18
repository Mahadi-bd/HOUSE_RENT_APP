import 'package:drift/drift.dart';
import 'package:rent_solution/core/security/audit_hash.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/tables/system_tables.dart';

part 'audit_dao.g.dart';

/// Result of checking an audit chain.
class AuditVerification {
  /// Creates a result.
  const AuditVerification({
    required this.ok,
    required this.checked,
    required this.headHash,
    this.brokenAtSeq,
    this.reason,
  });

  /// True when every record links to the one before and matches its own hash.
  final bool ok;

  /// How many records were checked.
  final int checked;

  /// Hash of the last good record (store it outside the database to detect truncation).
  final String headHash;

  /// Sequence number of the first bad record.
  final int? brokenAtSeq;

  /// Plain-language reason when [ok] is false.
  final String? reason;
}

/// Writes and verifies the audit chain. The only way to add audit rows.
@DriftAccessor(tables: [AuditLogs])
class AuditDao extends DatabaseAccessor<AppDatabase> with _$AuditDaoMixin {
  /// Creates the DAO.
  AuditDao(super.attachedDatabase);

  /// Appends one record, linked to the previous record of [orgId].
  Future<AuditLog> append({
    required String orgId,
    required String userId,
    required String action,
    required String entityType,
    required String entityId,
    String? oldValue,
    String? newValue,
    DateTime? at,
  }) {
    return transaction(() async {
      final last = await (select(auditLogs)
            ..where((a) => a.orgId.equals(orgId))
            ..orderBy([(a) => OrderingTerm.desc(a.seq)])
            ..limit(1))
          .getSingleOrNull();
      final prevHash = last?.currHash ?? auditGenesisHash;
      final id = newId();
      final seconds = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
      final currHash = computeAuditHash(
        prevHash: prevHash,
        payload: auditPayload(
          id: id,
          orgId: orgId,
          userId: userId,
          action: action,
          entityType: entityType,
          entityId: entityId,
          oldValue: oldValue,
          newValue: newValue,
          timestampSeconds: seconds,
        ),
      );
      await into(auditLogs).insert(
        AuditLogsCompanion.insert(
          id: id,
          orgId: orgId,
          userId: userId,
          action: action,
          entityType: entityType,
          entityId: entityId,
          oldValue: Value(oldValue),
          newValue: Value(newValue),
          prevHash: prevHash,
          currHash: currHash,
          timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
        ),
      );
      return (select(auditLogs)..where((a) => a.id.equals(id))).getSingle();
    });
  }

  /// Checks the whole chain of [orgId]. Pass [expectedHead] (kept outside the database, for
  /// example in a backup manifest) to also detect records removed from the end.
  Future<AuditVerification> verifyChain(String orgId, {String? expectedHead}) async {
    final rows = await (select(auditLogs)
          ..where((a) => a.orgId.equals(orgId))
          ..orderBy([(a) => OrderingTerm.asc(a.seq)]))
        .get();
    var expectedPrev = auditGenesisHash;
    for (final row in rows) {
      if (row.prevHash != expectedPrev) {
        return AuditVerification(
          ok: false,
          checked: rows.length,
          headHash: expectedPrev,
          brokenAtSeq: row.seq,
          reason: 'A record was removed or reordered before this one.',
        );
      }
      final recomputed = computeAuditHash(
        prevHash: row.prevHash,
        payload: auditPayload(
          id: row.id,
          orgId: row.orgId,
          userId: row.userId,
          action: row.action,
          entityType: row.entityType,
          entityId: row.entityId,
          oldValue: row.oldValue,
          newValue: row.newValue,
          timestampSeconds: row.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000,
        ),
      );
      if (recomputed != row.currHash) {
        return AuditVerification(
          ok: false,
          checked: rows.length,
          headHash: expectedPrev,
          brokenAtSeq: row.seq,
          reason: 'The content of this record was changed.',
        );
      }
      expectedPrev = row.currHash;
    }
    if (expectedHead != null && expectedHead != expectedPrev) {
      return AuditVerification(
        ok: false,
        checked: rows.length,
        headHash: expectedPrev,
        reason: 'Records are missing at the end of the log.',
      );
    }
    return AuditVerification(ok: true, checked: rows.length, headHash: expectedPrev);
  }

  /// Checks the chain AND the trusted checkpoint kept outside the database. The checkpoint
  /// record must still exist at the same position with the same hash, so a database that lost
  /// its newest records, or was replaced by an older copy, fails. A database that is AHEAD of
  /// the checkpoint is fine (the app may have stopped between commit and save).
  Future<AuditVerification> verifyWithCheckpoint(
    String orgId, {
    required int? checkpointSeq,
    required String? checkpointHead,
  }) async {
    final chain = await verifyChain(orgId);
    if (!chain.ok || checkpointSeq == null || checkpointHead == null) {
      return chain;
    }
    final row = await (select(auditLogs)
          ..where((a) => a.orgId.equals(orgId) & a.seq.equals(checkpointSeq)))
        .getSingleOrNull();
    if (row == null || row.currHash != checkpointHead) {
      return AuditVerification(
        ok: false,
        checked: chain.checked,
        headHash: chain.headHash,
        brokenAtSeq: checkpointSeq,
        reason: 'The trusted checkpoint is missing: records were removed or the database was replaced.',
      );
    }
    return chain;
  }
}
