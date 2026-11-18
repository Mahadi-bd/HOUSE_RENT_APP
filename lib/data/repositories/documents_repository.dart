import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as pth;
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Tenant documents (NID photos, agreements, tenant photo...), stored ENCRYPTED on the phone with
/// AES-256-GCM. A tenant photo is basic data (staff may see it for security). Everything else is
/// vault data: Owner/Admin, staff with approved vault access, or the tenant's own record.
class DocumentsRepository {
  /// Creates the repository. [root] is the app folder; files go to `root/vault/`.
  DocumentsRepository(this._db, this._guard, this._ctx, this._confirmations, this._keys, this._root);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;
  final VaultKeyStore _keys;
  final Directory _root;

  /// Largest file accepted.
  static const maxBytes = 10 * 1024 * 1024;

  static const _allowed = {'png', 'jpg', 'jpeg', 'pdf'};

  Future<Tenant> _tenant(String tenantId) async {
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    return tenant;
  }

  Future<String> _propertyOf(Tenant tenant) async => (await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle())
      .propertyId;

  Future<bool> _anyEncrypted() async => (await (_db.select(_db.documents)..limit(1)).get()).isNotEmpty;

  /// Encrypts and saves [bytes] for [tenantId] and returns the document id.
  Future<String> store({
    required String tenantId,
    required DocumentType type,
    required Uint8List bytes,
    required String extension,
  }) async {
    final sensitive = type != DocumentType.photo;
    _guard.require(sensitive ? Permission.tenantSensitiveWrite : Permission.tenantWrite);
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (!_allowed.contains(ext)) {
      throw ArgumentError('Only PNG, JPG and PDF files are accepted.');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('The file must be between 1 byte and 10 MB.');
    }
    final id = newId();
    final tenant = await _tenant(tenantId);
    _guard.requireInProperty(
      sensitive ? Permission.tenantSensitiveWrite : Permission.tenantWrite,
      await _propertyOf(tenant),
    );
    final crypto = await _keys.crypto(encryptedDataExists: await _anyEncrypted());
    final encrypted = await crypto.encrypt(bytes, id);
    final relative = pth.join('vault', '$id.bin');
    final file = File(pth.join(_root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encrypted, flush: true);
    try {
      await _ctx.transaction(_db, () async {
        final now = _ctx.now;
        await _db.into(_db.documents).insert(
              DocumentsCompanion.insert(
                id: id,
                orgId: _ctx.orgId,
                createdAt: now,
                updatedAt: now,
                createdBy: _ctx.userId,
                deviceId: _ctx.deviceId,
                hlc: _ctx.hlc,
                entityType: 'tenant',
                entityId: tenantId,
                localPath: relative,
                type: type,
                uploadedAt: now,
                sizeBytes: Value(bytes.length),
              ),
            );
        await _db.auditDao.append(
          orgId: _ctx.orgId,
          userId: _ctx.userId,
          action: 'document.add',
          entityType: 'document',
          entityId: id,
          newValue: jsonEncode({'tenantId': tenantId, 'type': type.name, 'ext': ext}),
          at: now,
        );
      });
    } on Object {
      if (file.existsSync()) {
        await file.delete();
      }
      rethrow;
    }
    return id;
  }

  /// Documents of [tenantId] this member may see: everything with vault access (or for the
  /// tenant's own record), otherwise only the tenant photo.
  Future<List<TenantDocument>> list(String tenantId) async {
    final tenant = await _tenant(tenantId);
    final propertyId = await _propertyOf(tenant);
    final a = _guard.access;
    final all = (a?.can(Permission.tenantSensitiveRead) ?? false) || (a?.isOwnTenant(tenantId) ?? false);
    if (!all) {
      _guard.requireInProperty(Permission.tenantBasicRead, propertyId);
    } else {
      _guard.requireOwnOrInProperty(
        tenantId: tenantId,
        propertyId: propertyId,
        permission: Permission.tenantSensitiveRead,
      );
    }
    final rows = await (_db.select(_db.documents)
          ..where(
            (d) =>
                d.entityId.equals(tenantId) &
                d.entityType.equals('tenant') &
                d.orgId.equals(_ctx.orgId) &
                d.deletedAt.isNull(),
          )
          ..orderBy([(d) => OrderingTerm.desc(d.uploadedAt)]))
        .get();
    return [
      for (final d in rows)
        if (all || d.type == DocumentType.photo) TenantDocument(d.id, d.type, d.sizeBytes, d.uploadedAt),
    ];
  }

  /// Decrypts and returns the file. Throws [DocumentTamperedException] if it was changed.
  Future<Uint8List> read(String documentId) async {
    final doc = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(documentId) & d.orgId.equals(_ctx.orgId) & d.deletedAt.isNull()))
        .getSingleOrNull();
    if (doc == null) {
      throw StateError('Document not found.');
    }
    final tenant = await _tenant(doc.entityId);
    if (doc.type == DocumentType.photo) {
      _guard.requireOwnOrInProperty(
        tenantId: tenant.id,
        propertyId: await _propertyOf(tenant),
        permission: Permission.tenantBasicRead,
      );
    } else {
      _guard.requireVaultRead(tenant.id);
      _guard.requireOwnOrInProperty(
        tenantId: tenant.id,
        propertyId: await _propertyOf(tenant),
        permission: Permission.tenantSensitiveRead,
      );
    }
    final file = File(pth.join(_root.path, doc.localPath));
    if (!file.existsSync()) {
      throw StateError('The document file is missing from this phone.');
    }
    final crypto = await _keys.crypto(encryptedDataExists: true);
    return crypto.decrypt(await file.readAsBytes(), doc.id);
  }

  /// Removes a document (a snapshot of its details goes to the 2-year archive; the encrypted file
  /// stays until the purge). Owner/Admin only, with a confirmation.
  Future<void> remove(
    String documentId, {
    required String reason,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.deleteAny);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is required.');
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.documentRemove,
      entityId: documentId,
    );
    await _ctx.transaction(_db, () async {
      final doc = await (_db.select(_db.documents)
            ..where(
              (d) => d.id.equals(documentId) & d.orgId.equals(_ctx.orgId) & d.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (doc == null) {
        throw StateError('Document not found.');
      }
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'document',
        entityId: documentId,
        snapshot: doc.toJson(),
      );
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(documentId) & d.orgId.equals(_ctx.orgId)))
          .write(
        DocumentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'document.remove',
        entityType: 'document',
        entityId: documentId,
        newValue: jsonEncode({'reason': reason.trim()}),
        at: now,
      );
    });
  }
}

/// A document listed for a tenant (no file contents).
class TenantDocument {
  /// Creates the description.
  const TenantDocument(this.id, this.type, this.sizeBytes, this.uploadedAt);

  /// Document id.
  final String id;

  /// What it is.
  final DocumentType type;

  /// Size of the original file.
  final int sizeBytes;

  /// When it was added.
  final DateTime uploadedAt;
}
