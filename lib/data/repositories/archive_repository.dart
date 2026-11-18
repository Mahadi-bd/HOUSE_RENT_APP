import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as pth;
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// The Deleted Items Archive: everything that was deleted stays for 2 years, can be brought back by
/// Owner/Admin, and is removed for good after that. Legal records are never purged.
class ArchiveRepository {
  /// Creates the repository. [root] is the app folder that holds the encrypted files.
  ArchiveRepository(this._db, this._guard, this._ctx, this._payments, this._root);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final PaymentsRepository _payments;
  final Directory _root;

  /// Types that can be restored.
  static const restorable = {
    'tenant',
    'payment',
    'extra_charge',
    'expense',
    'household_member',
    'document',
  };

  /// Archive entries that are still waiting (not restored, not purged), newest first.
  Future<List<DeletedArchive>> list() async {
    _guard.require(Permission.archiveRestore);
    return (_db.select(_db.deletedArchives)
          ..where((a) => a.orgId.equals(_ctx.orgId) & a.restoredAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.deletedAt)]))
        .get();
  }

  /// Brings an archived item back. Refused (nothing changes) if it would clash with newer data,
  /// for example the unit now has another tenant.
  Future<void> restore(String archiveId) async {
    _guard.require(Permission.archiveRestore);
    await _ctx.transaction(_db, () async {
      final entry = await (_db.select(_db.deletedArchives)
            ..where((a) => a.id.equals(archiveId) & a.orgId.equals(_ctx.orgId) & a.restoredAt.isNull()))
          .getSingleOrNull();
      if (entry == null) {
        throw StateError('Archive entry not found.');
      }
      if (!restorable.contains(entry.entityType)) {
        throw StateError('This kind of item cannot be restored.');
      }
      final now = _ctx.now;
      switch (entry.entityType) {
        case 'payment':
          await _payments.restorePayment(entry.entityId);
        case 'extra_charge':
          await _undelete(_db.extraCharges, entry.entityId, now);
        case 'expense':
          await _undelete(_db.expenses, entry.entityId, now);
        case 'document':
          await _undelete(_db.documents, entry.entityId, now);
        case 'household_member':
          await _undelete(_db.householdMembers, entry.entityId, now);
          final vault = await (_db.select(_db.householdVaults)
                ..where((v) => v.householdMemberId.equals(entry.entityId) & v.orgId.equals(_ctx.orgId)))
              .get();
          for (final v in vault) {
            await _undelete(_db.householdVaults, v.id, now);
          }
        case 'tenant':
          await _restoreTenant(entry.entityId, now);
      }
      await (_db.update(_db.deletedArchives)..where((a) => a.id.equals(archiveId))).write(
        DeletedArchivesCompanion(
          restoredAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'archive.restore',
        entityType: entry.entityType,
        entityId: entry.entityId,
        at: now,
      );
    });
  }

  Future<void> _undelete(TableInfo<Table, dynamic> table, String id, DateTime now) {
    return _db.customUpdate(
      'UPDATE ${table.actualTableName} SET deleted_at = NULL, updated_at = ?, hlc = ?, sync_status = ? '
      'WHERE id = ? AND org_id = ? AND deleted_at IS NOT NULL',
      variables: [
        Variable<DateTime>(now),
        Variable<String>(_ctx.hlc),
        Variable<String>(SyncStatus.pending.name),
        Variable<String>(id),
        Variable<String>(_ctx.orgId),
      ],
      updates: {table},
    );
  }

  Future<void> _restoreTenant(String tenantId, DateTime now) async {
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNotNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    if (tenant.name == erasedName) {
      throw StateError('This tenant\'s personal data was erased on a legal notice and cannot be restored.');
    }
    final others = await (_db.select(_db.tenants)
          ..where(
            (t) =>
                t.unitId.equals(tenant.unitId) &
                t.orgId.equals(_ctx.orgId) &
                t.id.equals(tenantId).not() &
                t.deletedAt.isNull() &
                t.status.isIn([TenantStatus.active.name, TenantStatus.notice.name]),
          ))
        .get();
    if (others.isNotEmpty) {
      throw StateError('This unit already has an active tenant.');
    }
    await (_db.update(_db.tenants)..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId))).write(
      TenantsCompanion(
        deletedAt: const Value(null),
        status: Value(TenantStatus.active),
        updatedAt: Value(now),
        hlc: Value(_ctx.hlc),
        syncStatus: Value(SyncStatus.pending),
      ),
    );
    await (_db.update(_db.units)..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId))).write(
      UnitsCompanion(
        status: Value(UnitStatus.occupied),
        updatedAt: Value(now),
        hlc: Value(_ctx.hlc),
        syncStatus: Value(SyncStatus.pending),
      ),
    );
  }

  /// The name that replaces a tenant's real name after a legal erasure.
  static const erasedName = '[erased]';

  /// Removes for good every archived item whose 2 years are over, and the data it points to.
  /// A tenant is not deleted but reduced to a stub (legal records and the police-share log stay).
  /// Returns how many archive entries were purged.
  Future<int> purgeExpired() async {
    _guard.require(Permission.archiveRestore);
    var purged = 0;
    await _ctx.transaction(_db, () async {
      final now = _ctx.now;
      final due = await (_db.select(_db.deletedArchives)
            ..where((a) => a.orgId.equals(_ctx.orgId) & a.purgeAfter.isSmallerOrEqualValue(now) & a.restoredAt.isNull()))
          .get();
      for (final entry in due) {
        switch (entry.entityType) {
          case 'payment':
            await _hardDelete('payments', entry.entityId);
          case 'extra_charge':
            await _hardDelete('extra_charges', entry.entityId);
          case 'expense':
            await _hardDelete('expenses', entry.entityId);
          case 'household_member':
            await _db.customUpdate(
              'DELETE FROM household_vaults WHERE household_member_id = ? AND org_id = ?',
              variables: [Variable<String>(entry.entityId), Variable<String>(_ctx.orgId)],
              updates: {_db.householdVaults},
            );
            await _hardDelete('household_members', entry.entityId);
          case 'document':
            await _deleteDocumentFile(entry.entityId);
            await _hardDelete('documents', entry.entityId);
          case 'tenant':
            await eraseTenantPersonalData(entry.entityId, keepDocumentsOfType: const {});
        }
        await _db.customUpdate(
          'DELETE FROM deleted_archives WHERE id = ? AND org_id = ?',
          variables: [Variable<String>(entry.id), Variable<String>(_ctx.orgId)],
          updates: {_db.deletedArchives},
        );
        purged++;
      }
      if (purged > 0) {
        await _db.auditDao.append(
          orgId: _ctx.orgId,
          userId: _ctx.userId,
          action: 'archive.purge',
          entityType: 'archive',
          entityId: _ctx.orgId,
          newValue: jsonEncode({'entries': purged}),
          at: now,
        );
      }
    });
    return purged;
  }

  Future<void> _hardDelete(String table, String id) async {
    await _db.customStatement('DELETE FROM $table WHERE id = ? AND org_id = ?', [id, _ctx.orgId]);
  }

  Future<void> _deleteDocumentFile(String documentId) async {
    final doc = await (_db.select(_db.documents)..where((d) => d.id.equals(documentId) & d.orgId.equals(_ctx.orgId))).getSingleOrNull();
    if (doc == null) {
      return;
    }
    final file = File(pth.join(_root.path, doc.localPath));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Erases the personal data of one tenant: private details, household, documents (files too,
  /// except the types in [keepDocumentsOfType]), archive snapshots about them, and turns the tenant
  /// into a stub (name "[erased]", no phone, no email, no photo). Payments (amounts only), legal
  /// records, the police-share log, lease dates and the unit stay. Used by purge and by legal erasure.
  Future<void> eraseTenantPersonalData(String tenantId, {required Set<DocumentType> keepDocumentsOfType}) async {
    final org = _ctx.orgId;
    final now = _ctx.now;
    final members = await (_db.select(_db.householdMembers)..where((m) => m.tenantId.equals(tenantId) & m.orgId.equals(org))).get();
    final memberIds = [for (final m in members) m.id];
    for (final id in memberIds) {
      await _db.customStatement('DELETE FROM household_vaults WHERE household_member_id = ? AND org_id = ?', [id, org]);
    }
    await _db.customStatement('DELETE FROM household_members WHERE tenant_id = ? AND org_id = ?', [tenantId, org]);
    await _db.customStatement('DELETE FROM tenant_vaults WHERE tenant_id = ? AND org_id = ?', [tenantId, org]);
    final docs = await (_db.select(_db.documents)
          ..where((d) => d.entityId.equals(tenantId) & d.entityType.equals('tenant') & d.orgId.equals(org)))
        .get();
    for (final d in docs) {
      if (keepDocumentsOfType.contains(d.type)) {
        continue;
      }
      await _deleteDocumentFile(d.id);
      await _db.customStatement('DELETE FROM ocr_scans WHERE image_doc_id = ? AND org_id = ?', [d.id, org]);
      await _db.customStatement('DELETE FROM documents WHERE id = ? AND org_id = ?', [d.id, org]);
    }
    // Archive snapshots that still hold this tenant's personal data.
    final archives = await (_db.select(_db.deletedArchives)..where((a) => a.orgId.equals(org))).get();
    for (final a in archives) {
      final about = a.entityId == tenantId ||
          memberIds.contains(a.entityId) ||
          docs.any((d) => d.id == a.entityId) ||
          a.snapshot.contains(tenantId);
      if (about && (a.entityType == 'tenant' || a.entityType == 'household_member' || a.entityType == 'document')) {
        await _db.customStatement('DELETE FROM deleted_archives WHERE id = ? AND org_id = ?', [a.id, org]);
      }
    }
    await (_db.update(_db.tenants)..where((t) => t.id.equals(tenantId) & t.orgId.equals(org))).write(
      TenantsCompanion(
        name: const Value(erasedName),
        phone: const Value(''),
        email: const Value(null),
        photoPath: const Value(null),
        updatedAt: Value(now),
        hlc: Value(_ctx.hlc),
        syncStatus: Value(SyncStatus.pending),
      ),
    );
  }
}
