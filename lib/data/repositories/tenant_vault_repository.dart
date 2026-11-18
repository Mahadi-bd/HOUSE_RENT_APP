import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/id_numbers.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// A tenant's sensitive details: NID number, permanent address, emergency contact.
/// Read: Owner/Admin, staff with approved vault access, or the tenant themselves.
/// Write: Owner/Admin or staff with approved vault write access. Values never go to the audit log.
class TenantVaultRepository {
  /// Creates the repository.
  TenantVaultRepository(this._db, this._guard, this._ctx);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;

  /// The vault details of a tenant (null if none saved). Vault access or the tenant's own record.
  Future<TenantVault?> get(String tenantId) async {
    _guard.requireVaultRead(tenantId);
    await _requireTenant(tenantId);
    return (_db.select(_db.tenantVaults)
          ..where(
            (v) => v.tenantId.equals(tenantId) & v.orgId.equals(_ctx.orgId) & v.deletedAt.isNull(),
          ))
        .getSingleOrNull();
  }

  Future<Tenant> _requireTenant(String tenantId) async {
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    return tenant;
  }

  /// Saves vault details. A null field is left alone; an empty text clears it.
  Future<void> save(
    String tenantId, {
    String? nidNo,
    String? permanentAddress,
    String? emergencyContact,
  }) async {
    _guard.require(Permission.tenantSensitiveWrite);
    String? cleanNid;
    if (nidNo != null && nidNo.trim().isNotEmpty) {
      cleanNid = normalizeNid(nidNo);
      if (cleanNid == null) {
        throw ArgumentError('The NID number must have 10, 13 or 17 digits.');
      }
    }
    await _ctx.transaction(_db, () async {
      final tenant = await _requireTenant(tenantId);
      final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle();
      _guard.requireInProperty(Permission.tenantSensitiveWrite, unit.propertyId);
      final existing = await (_db.select(_db.tenantVaults)
            ..where(
              (v) =>
                  v.tenantId.equals(tenantId) & v.orgId.equals(_ctx.orgId) & v.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      final now = _ctx.now;
      Value<String?> field(String? input, String? cleaned) {
        if (input == null) {
          return const Value.absent();
        }
        return Value(cleaned ?? (input.trim().isEmpty ? null : input.trim()));
      }

      final changed = [
        if (nidNo != null) 'nidNo',
        if (permanentAddress != null) 'permanentAddress',
        if (emergencyContact != null) 'emergencyContact',
      ];
      if (existing == null) {
        await _db.into(_db.tenantVaults).insert(
              TenantVaultsCompanion.insert(
                id: newId(),
                orgId: _ctx.orgId,
                createdAt: now,
                updatedAt: now,
                createdBy: _ctx.userId,
                deviceId: _ctx.deviceId,
                hlc: _ctx.hlc,
                tenantId: tenantId,
                nidNo: field(nidNo, cleanNid),
                permanentAddress: field(permanentAddress, null),
                emergencyContact: field(emergencyContact, null),
              ),
            );
      } else {
        await (_db.update(_db.tenantVaults)
              ..where((v) => v.id.equals(existing.id) & v.orgId.equals(_ctx.orgId)))
            .write(
          TenantVaultsCompanion(
            nidNo: field(nidNo, cleanNid),
            permanentAddress: field(permanentAddress, null),
            emergencyContact: field(emergencyContact, null),
            updatedAt: Value(now),
            hlc: Value(_ctx.hlc),
            syncStatus: Value(SyncStatus.pending),
          ),
        );
      }
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'vault.save',
        entityType: 'tenant_vault',
        entityId: tenantId,
        // Only WHICH fields changed, never their values.
        newValue: jsonEncode({'fields': changed}),
        at: now,
      );
    });
  }
}
