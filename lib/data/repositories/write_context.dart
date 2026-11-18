import 'package:drift/drift.dart';
import 'package:rent_solution/core/security/audit_checkpoint.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/sync/hlc.dart';

/// Who is writing, on which device, and when. Passed to every repository.
class WriteContext {
  /// Creates a context. Pass [clock] in tests to fix the time.
  WriteContext({
    required this.orgId,
    required this.userId,
    required this.deviceId,
    DateTime Function()? clock,
    this.checkpoints,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// Organization the rows belong to.
  final String orgId;

  /// The signed-in user.
  final String userId;

  /// This installation.
  final String deviceId;

  /// Where the trusted audit head is saved after every committed change (optional in tests).
  final AuditCheckpointStore? checkpoints;

  final DateTime Function() _clock;

  /// Current time in UTC.
  DateTime get now => _clock();

  /// A fresh clock stamp for a new or changed row.
  String get hlc => hlcNow(deviceId);

  /// Runs [body] in one database transaction. After it COMMITS, the newest audit head is saved
  /// outside the database, so a rolled-back change can never leave the checkpoint ahead.
  Future<T> transaction<T>(AppDatabase db, Future<T> Function() body) async {
    final result = await db.transaction(body);
    final store = checkpoints;
    if (store != null) {
      final last = await (db.select(db.auditLogs)
            ..where((a) => a.orgId.equals(orgId))
            ..orderBy([(a) => OrderingTerm.desc(a.seq)])
            ..limit(1))
          .getSingleOrNull();
      if (last != null) {
        await store.save(orgId, AuditCheckpoint(last.seq, last.currHash));
      }
    }
    return result;
  }
}
