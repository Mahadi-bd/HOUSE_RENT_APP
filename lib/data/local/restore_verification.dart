import 'package:rent_solution/core/security/audit_checkpoint.dart';
import 'package:rent_solution/data/local/daos/audit_dao.dart';
import 'package:rent_solution/data/local/database.dart';

/// Checks a database that was just restored from a backup: every audit record links and hashes
/// correctly, and the trusted checkpoint kept outside the database is still inside the chain.
/// A restore must be refused (or clearly warned) when this is not ok.
Future<AuditVerification> verifyRestoredDatabase(
  AppDatabase restored,
  AuditCheckpointStore checkpoints,
  String orgId,
) async {
  final checkpoint = await checkpoints.load(orgId);
  return restored.auditDao.verifyWithCheckpoint(
    orgId,
    checkpointSeq: checkpoint?.seq,
    checkpointHead: checkpoint?.head,
  );
}
