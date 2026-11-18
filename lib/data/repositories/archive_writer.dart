import 'dart:convert';

import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Writes the snapshot that goes into the 2-year Deleted Items Archive.
/// Today the snapshot is JSON protected by the whole-database encryption; a separate
/// field-level key arrives with Phase 5.
class ArchiveWriter {
  const ArchiveWriter._();

  /// How long deleted items are kept before they may be purged.
  static const retention = Duration(days: 730);

  /// Stores [snapshot] of one deleted record. Call inside the same transaction as the delete.
  static Future<void> archive(
    AppDatabase db,
    WriteContext ctx, {
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    final now = ctx.now;
    await db.into(db.deletedArchives).insert(
          DeletedArchivesCompanion.insert(
            id: newId(),
            orgId: ctx.orgId,
            createdAt: now,
            updatedAt: now,
            createdBy: ctx.userId,
            deviceId: ctx.deviceId,
            hlc: ctx.hlc,
            entityType: entityType,
            entityId: entityId,
            snapshot: jsonEncode(snapshot),
            deletedBy: ctx.userId,
            deletedAt: now,
            purgeAfter: now.add(retention),
          ),
        );
  }
}
