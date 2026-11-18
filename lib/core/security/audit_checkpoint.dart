import 'package:rent_solution/core/storage/key_value_store.dart';

/// The newest audit record that was known to be good, kept OUTSIDE the database
/// (Keystore/Keychain) so a replaced or truncated database file can be detected.
class AuditCheckpoint {
  /// Creates a checkpoint.
  const AuditCheckpoint(this.seq, this.head);

  /// Sequence number of the newest record.
  final int seq;

  /// Its hash.
  final String head;
}

/// Saves and loads [AuditCheckpoint]s, one per organization.
class AuditCheckpointStore {
  /// Creates the store.
  const AuditCheckpointStore(this._store);

  final KeyValueStore _store;

  String _key(String orgId) => 'audit_checkpoint_v1_$orgId';

  /// The saved checkpoint, or null if none.
  Future<AuditCheckpoint?> load(String orgId) async {
    final raw = await _store.read(_key(orgId));
    if (raw == null) {
      return null;
    }
    final parts = raw.split(':');
    final seq = parts.length == 2 ? int.tryParse(parts[0]) : null;
    if (seq == null) {
      return null;
    }
    return AuditCheckpoint(seq, parts[1]);
  }

  /// Saves [checkpoint]. A lower sequence number never replaces a higher one.
  Future<void> save(String orgId, AuditCheckpoint checkpoint) async {
    final current = await load(orgId);
    if (current != null && current.seq >= checkpoint.seq) {
      return;
    }
    await _store.write(_key(orgId), '${checkpoint.seq}:${checkpoint.head}');
  }
}
