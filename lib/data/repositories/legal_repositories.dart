import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_repository.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Legal notices and NOCs. They are kept for the owner's protection: never purged, Owner/Admin only.
class LegalRecordsRepository {
  /// Creates the repository.
  LegalRecordsRepository(this._db, this._guard, this._ctx, this._documents);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final DocumentsRepository _documents;

  /// Stores the scan (encrypted) and the record. Works for tenants who already moved out too.
  Future<String> add({
    required String tenantId,
    required LegalRecordKind kind,
    required DateTime issuedOn,
    required Uint8List bytes,
    required String extension,
    String? referenceNo,
  }) async {
    _guard.require(Permission.legalRecords);
    final documentId = await _documents.store(
      tenantId: tenantId,
      type: kind == LegalRecordKind.legalNotice ? DocumentType.legalNotice : DocumentType.noc,
      bytes: bytes,
      extension: extension,
      allowMovedOut: true,
    );
    final id = newId();
    final now = _ctx.now;
    final reference = referenceNo?.trim();
    await _ctx.transaction(_db, () async {
      await _db.into(_db.legalRecords).insert(
            LegalRecordsCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              kind: kind,
              issuedOn: issuedOn,
              documentId: documentId,
              referenceNo: Value(reference == null || reference.isEmpty ? null : reference),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'legal.add',
        entityType: 'legal_record',
        entityId: id,
        newValue: jsonEncode({'tenantId': tenantId, 'kind': kind.name}),
        at: now,
      );
    });
    return id;
  }

  /// Legal records of a tenant, newest first.
  Future<List<LegalRecord>> list(String tenantId) async {
    _guard.require(Permission.legalRecords);
    return (_db.select(_db.legalRecords)
          ..where(
            (r) => r.tenantId.equals(tenantId) & r.orgId.equals(_ctx.orgId) & r.deletedAt.isNull(),
          )
          ..orderBy([(r) => OrderingTerm.desc(r.issuedOn)]))
        .get();
  }
}

/// Erases a tenant's personal data on a legal notice. Kept: the legal notice and NOC files and
/// records, the police-share log, payments (amounts only, no name), lease dates and the unit.
class LegalErasureRepository {
  /// Creates the repository.
  LegalErasureRepository(this._db, this._guard, this._ctx, this._confirmations, this._archive);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;
  final ArchiveRepository _archive;

  /// Erases the personal data of a tenant who has already moved out. Needs a legal notice record
  /// for this tenant and an email confirmation for exactly this tenant.
  Future<void> eraseTenant(
    String tenantId, {
    required String legalRecordId,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.legalRecords);
    _confirmations.consume(confirmation, action: SensitiveAction.legalErasure, entityId: tenantId);
    await _ctx.transaction(_db, () async {
      final tenant = await (_db.select(_db.tenants)
            ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId)))
          .getSingleOrNull();
      if (tenant == null) {
        throw StateError('Tenant not found.');
      }
      if (tenant.deletedAt == null) {
        throw StateError('Move the tenant out first.');
      }
      final record = await (_db.select(_db.legalRecords)
            ..where(
              (r) =>
                  r.id.equals(legalRecordId) &
                  r.tenantId.equals(tenantId) &
                  r.orgId.equals(_ctx.orgId) &
                  r.deletedAt.isNull() &
                  r.kind.equalsValue(LegalRecordKind.legalNotice),
            ))
          .getSingleOrNull();
      if (record == null) {
        throw StateError('A legal notice for this tenant is required.');
      }
      await _archive.eraseTenantPersonalData(
        tenantId,
        keepDocumentsOfType: const {DocumentType.legalNotice, DocumentType.noc},
      );
      final now = _ctx.now;
      await _db.into(_db.erasureRequests).insert(
            ErasureRequestsCompanion.insert(
              id: newId(),
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              legalRecordId: legalRecordId,
              requestedBy: _ctx.userId,
              approvedBy: Value(_ctx.userId),
              erasedAt: Value(now),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'legal.erase',
        entityType: 'tenant',
        entityId: tenantId,
        newValue: jsonEncode({'legalRecordId': legalRecordId}),
        at: now,
      );
    });
  }
}
