import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Tenant data access with permission checks and audit records. UI code must use this,
/// never the DAO or the tables directly.
class TenantsRepository {
  /// Creates the repository.
  TenantsRepository(this._db, this._guard, this._ctx, this._confirmations);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;

  /// Active tenants. Needs basic tenant read permission.
  Stream<List<Tenant>> watchActive() {
    _guard.require(Permission.tenantBasicRead);
    return _db.tenantsDao.watchActive(_ctx.orgId);
  }

  /// One tenant. A tenant member can open only their own record.
  Future<Tenant> getById(String id) async {
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(id) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    final unit = await (_db.select(_db.units)
          ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
        .getSingle();
    _guard.requireOwnOrInProperty(
      tenantId: id,
      propertyId: unit.propertyId,
      permission: Permission.tenantBasicRead,
    );
    return tenant;
  }

  /// Adds a tenant to a vacant unit. Money is in poisha. Returns the tenant id.
  Future<String> create({
    required String name,
    required String phone,
    required String unitId,
    required DateTime leaseStart,
    required int monthlyRent,
    int serviceCharge = 0,
    String? email,
    DateTime? leaseEnd,
  }) async {
    _guard.require(Permission.tenantWrite);
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (name.trim().isEmpty) {
      throw ArgumentError('Tenant name is required.');
    }
    if (!RegExp(r'^\d{10,15}$').hasMatch(cleanPhone)) {
      throw ArgumentError('Phone number must have 10 to 15 digits.');
    }
    if (monthlyRent <= 0 || serviceCharge < 0) {
      throw ArgumentError('Rent must be above zero and service charge cannot be negative.');
    }
    if (leaseEnd != null && !leaseEnd.isAfter(leaseStart)) {
      throw ArgumentError('Lease end must be after lease start.');
    }
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(unitId) & u.orgId.equals(_ctx.orgId) & u.deletedAt.isNull()))
          .getSingleOrNull();
      if (unit == null) {
        throw StateError('Unit not found.');
      }
      _guard.requireInProperty(Permission.tenantWrite, unit.propertyId);
      final existing = await (_db.select(_db.tenants)
            ..where(
              (t) =>
                  t.unitId.equals(unitId) &
                  t.orgId.equals(_ctx.orgId) &
                  t.deletedAt.isNull() &
                  t.status.isIn([TenantStatus.active.name, TenantStatus.notice.name]),
            ))
          .get();
      if (existing.isNotEmpty) {
        throw StateError('This unit already has an active tenant.');
      }
      await _db.into(_db.tenants).insert(
            TenantsCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              name: name.trim(),
              phone: cleanPhone,
              unitId: unitId,
              leaseStart: leaseStart,
              monthlyRent: monthlyRent,
              serviceCharge: Value(serviceCharge),
              email: Value(email),
              leaseEnd: Value(leaseEnd),
            ),
          );
      await (_db.update(_db.units)..where((u) => u.id.equals(unitId))).write(
        UnitsCompanion(
          status: Value(UnitStatus.occupied),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'tenant.create',
        entityType: 'tenant',
        entityId: id,
        // No phone, NID or address in the audit log.
        newValue: jsonEncode({'unitId': unitId, 'monthlyRent': monthlyRent}),
        at: now,
      );
    });
    return id;
  }

  /// Whether the rent of [tenantId] may still be changed. Until monthly bills keep a rent
  /// history (Phase 4), changing rent after a payment exists would rewrite past months, so it
  /// is refused.
  Future<bool> canEditRent(String tenantId) async {
    final payments = await (_db.select(_db.payments)
          ..where(
            (p) => p.tenantId.equals(tenantId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
          )
          ..limit(1))
        .get();
    return payments.isEmpty;
  }

  /// Changes a tenant's name, phone, email or lease end, and (only before any payment exists)
  /// the monthly rent and service charge. Money is in poisha.
  Future<void> update(
    String id, {
    String? name,
    String? phone,
    String? email,
    DateTime? leaseEnd,
    bool clearLeaseEnd = false,
    int? monthlyRent,
    int? serviceCharge,
  }) async {
    _guard.require(Permission.tenantWrite);
    final cleanPhone = phone?.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError('Tenant name is required.');
    }
    if (cleanPhone != null && !RegExp(r'^\d{10,15}$').hasMatch(cleanPhone)) {
      throw ArgumentError('Phone number must have 10 to 15 digits.');
    }
    if ((monthlyRent != null && monthlyRent <= 0) || (serviceCharge != null && serviceCharge < 0)) {
      throw ArgumentError('Rent must be above zero and service charge cannot be negative.');
    }
    await _ctx.transaction(_db, () async {
      final tenant = await (_db.select(_db.tenants)
            ..where((t) => t.id.equals(id) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (tenant == null) {
        throw StateError('Tenant not found.');
      }
      final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle();
      _guard.requireInProperty(Permission.tenantWrite, unit.propertyId);
      final changesMoney = (monthlyRent != null && monthlyRent != tenant.monthlyRent) ||
          (serviceCharge != null && serviceCharge != tenant.serviceCharge);
      if (changesMoney && !await canEditRent(id)) {
        throw StateError('Rent cannot be changed after payments exist.');
      }
      if (leaseEnd != null && !leaseEnd.isAfter(tenant.leaseStart)) {
        throw ArgumentError('Lease end must be after lease start.');
      }
      final now = _ctx.now;
      await (_db.update(_db.tenants)..where((t) => t.id.equals(id) & t.orgId.equals(_ctx.orgId)))
          .write(
        TenantsCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          phone: cleanPhone == null ? const Value.absent() : Value(cleanPhone),
          email: email == null ? const Value.absent() : Value(email.trim().isEmpty ? null : email.trim()),
          leaseEnd: clearLeaseEnd
              ? const Value(null)
              : leaseEnd == null
                  ? const Value.absent()
                  : Value(leaseEnd),
          monthlyRent: monthlyRent == null ? const Value.absent() : Value(monthlyRent),
          serviceCharge: serviceCharge == null ? const Value.absent() : Value(serviceCharge),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'tenant.update',
        entityType: 'tenant',
        entityId: id,
        // Names and phone numbers stay out of the audit log; only money changes are recorded.
        oldValue: jsonEncode({'monthlyRent': tenant.monthlyRent, 'serviceCharge': tenant.serviceCharge}),
        newValue: jsonEncode({
          'monthlyRent': monthlyRent ?? tenant.monthlyRent,
          'serviceCharge': serviceCharge ?? tenant.serviceCharge,
        }),
        at: now,
      );
    });
  }

  /// Moves a tenant out. Owner/Admin only, with a [confirmation] for exactly this tenant.
  ///
  /// One transaction: snapshot into the 2-year archive, mark the tenant moved out and hidden
  /// (clock and sync state updated), free the unit only if no other active tenant remains,
  /// and write the audit record. Any failure leaves nothing changed.
  Future<void> softDelete(String id, {required ConfirmationToken confirmation}) async {
    _guard.require(Permission.deleteAny);
    _confirmations.consume(confirmation, action: SensitiveAction.tenantDelete, entityId: id);
    await _ctx.transaction(_db, () async {
      final tenant = await (_db.select(_db.tenants)
            ..where((t) => t.id.equals(id) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (tenant == null) {
        throw StateError('Tenant not found.');
      }
      final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle();
      _guard.requireInProperty(Permission.deleteAny, unit.propertyId);
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'tenant',
        entityId: id,
        snapshot: {'tenant': tenant.toJson(), 'unitStatusBefore': unit.status.name},
      );
      await _db.tenantsDao.softDelete(_ctx.orgId, id, now, _ctx.hlc);
      final others = await (_db.select(_db.tenants)
            ..where(
              (t) =>
                  t.unitId.equals(unit.id) &
                  t.orgId.equals(_ctx.orgId) &
                  t.id.equals(id).not() &
                  t.deletedAt.isNull() &
                  t.status.isIn([TenantStatus.active.name, TenantStatus.notice.name]),
            ))
          .get();
      var unitFreed = false;
      if (others.isEmpty) {
        await (_db.update(_db.units)
              ..where((u) => u.id.equals(unit.id) & u.orgId.equals(_ctx.orgId)))
            .write(
          UnitsCompanion(
            status: Value(UnitStatus.vacant),
            updatedAt: Value(now),
            hlc: Value(_ctx.hlc),
            syncStatus: Value(SyncStatus.pending),
          ),
        );
        unitFreed = true;
      }
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'tenant.delete',
        entityType: 'tenant',
        entityId: id,
        newValue: jsonEncode({'unitId': unit.id, 'unitFreed': unitFreed}),
        at: now,
      );
    });
  }
}
