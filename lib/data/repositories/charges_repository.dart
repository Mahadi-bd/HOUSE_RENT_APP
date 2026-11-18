import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Optional extra charges on top of rent: electricity, gas, water, internet, fines, damage, other.
/// Adding none is normal. Owner, Admin and Manager can add; only Owner/Admin can remove
/// (after email confirmation), like every deletion.
class ChargesRepository {
  /// Creates the repository.
  ChargesRepository(this._db, this._guard, this._ctx, this._confirmations);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;

  static final _monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  /// Adds a charge of [amount] poisha for [month] (`yyyy-MM`) and returns its id.
  /// "Other" charges need a [label] so everyone knows what it is for.
  Future<String> addCharge({
    required String tenantId,
    required String month,
    required ChargeKind kind,
    required int amount,
    String? label,
    String? note,
  }) async {
    _guard.require(Permission.chargeWrite);
    if (!_monthPattern.hasMatch(month)) {
      throw ArgumentError.value(month, 'month', 'must look like 2026-11');
    }
    if (amount <= 0 || amount > PaymentsRepository.maxAmount) {
      throw ArgumentError.value(amount, 'amount', 'must be above zero (poisha)');
    }
    if (kind == ChargeKind.other && (label == null || label.trim().isEmpty)) {
      throw ArgumentError('A label is required for an "other" charge.');
    }
    final id = newId();
    await _ctx.transaction(_db, () async {
      final tenant = await (_db.select(_db.tenants)
            ..where(
              (t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (tenant == null) {
        throw StateError('Tenant not found.');
      }
      final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle();
      _guard.requireInProperty(Permission.chargeWrite, unit.propertyId);
      final now = _ctx.now;
      await _db.into(_db.extraCharges).insert(
            ExtraChargesCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              unitId: tenant.unitId,
              month: month,
              kind: kind,
              amount: amount,
              label: Value(label?.trim()),
              note: Value(note),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'charge.add',
        entityType: 'extra_charge',
        entityId: id,
        newValue: jsonEncode({
          'tenantId': tenantId,
          'month': month,
          'kind': kind.name,
          'amount': amount,
        }),
        at: now,
      );
    });
    return id;
  }

  /// Removes a charge (it is kept, marked deleted). Owner/Admin only, after email confirmation.
  Future<void> voidCharge(
    String chargeId, {
    required String reason,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.deleteAny);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is required.');
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.chargeVoid,
      entityId: chargeId,
    );
    await _ctx.transaction(_db, () async {
      final old = await (_db.select(_db.extraCharges)
            ..where(
              (c) => c.id.equals(chargeId) & c.orgId.equals(_ctx.orgId) & c.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (old == null) {
        throw StateError('Charge not found.');
      }
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'extra_charge',
        entityId: chargeId,
        snapshot: old.toJson(),
      );
      await (_db.update(_db.extraCharges)
            ..where((c) => c.id.equals(chargeId) & c.orgId.equals(_ctx.orgId)))
          .write(
        ExtraChargesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'charge.void',
        entityType: 'extra_charge',
        entityId: chargeId,
        oldValue: jsonEncode({'kind': old.kind.name, 'amount': old.amount, 'month': old.month}),
        newValue: jsonEncode({'reason': reason.trim()}),
        at: now,
      );
    });
  }

  /// Extra charges of [tenantId], newest month first. A tenant can read only their own.
  Future<List<ExtraCharge>> listForTenant(String tenantId) async {
    final tenant = await (_db.select(_db.tenants)
          ..where(
            (t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull(),
          ))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    final unit = await (_db.select(_db.units)
            ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
          .getSingle();
    _guard.requireOwnOrInProperty(
      tenantId: tenantId,
      propertyId: unit.propertyId,
      permission: Permission.paymentCreate,
    );
    return (_db.select(_db.extraCharges)
          ..where(
            (c) => c.tenantId.equals(tenantId) & c.orgId.equals(_ctx.orgId) & c.deletedAt.isNull(),
          )
          ..orderBy([(c) => OrderingTerm.desc(c.month), (c) => OrderingTerm.desc(c.createdAt)]))
        .get();
  }
}
