import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/id_numbers.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/core/utils/phone_utils.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Everyone living with or working for a tenant (family, domestic workers, drivers, guards).
/// Names, relations and ages are basic data that staff may see for security. Phone numbers and
/// ID numbers are vault data: only people with vault access can read or write them.
class HouseholdRepository {
  /// Creates the repository.
  HouseholdRepository(this._db, this._guard, this._ctx, this._confirmations);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;

  /// Most people one tenant can list (a typing-error guard).
  static const maxMembers = 30;

  Future<Tenant> _tenant(String tenantId) async {
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    return tenant;
  }

  Future<String> _propertyOf(Tenant tenant) async {
    final unit = await (_db.select(_db.units)
          ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
        .getSingle();
    return unit.propertyId;
  }

  Future<HouseholdMember> _member(String memberId) async {
    final row = await (_db.select(_db.householdMembers)
          ..where((m) => m.id.equals(memberId) & m.orgId.equals(_ctx.orgId) & m.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Household member not found.');
    }
    return row;
  }

  /// Household members (basic data only). A tenant member can read only their own household.
  Future<List<HouseholdMember>> listBasic(String tenantId) async {
    final tenant = await _tenant(tenantId);
    _guard.requireOwnOrInProperty(
      tenantId: tenantId,
      propertyId: await _propertyOf(tenant),
      permission: Permission.householdBasicRead,
    );
    return (_db.select(_db.householdMembers)
          ..where(
            (m) => m.tenantId.equals(tenantId) & m.orgId.equals(_ctx.orgId) & m.deletedAt.isNull(),
          )
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
  }

  /// People in the home: the tenant plus every household member.
  Future<int> memberCount(String tenantId) async => 1 + (await listBasic(tenantId)).length;

  /// Phone and ID number of one member. Vault access only (or the tenant's own record).
  Future<HouseholdVault?> vaultOf(String memberId) async {
    final member = await _member(memberId);
    _guard.requireVaultRead(member.tenantId);
    return (_db.select(_db.householdVaults)
          ..where(
            (v) =>
                v.householdMemberId.equals(memberId) &
                v.orgId.equals(_ctx.orgId) &
                v.deletedAt.isNull(),
          ))
        .getSingleOrNull();
  }

  /// Adds a member and returns the id. [phone] and [idNo] need vault write access.
  Future<String> addMember({
    required String tenantId,
    required HouseholdType type,
    required String name,
    String? relation,
    int? age,
    String? note,
    String? phone,
    String? idNo,
  }) async {
    _guard.require(Permission.tenantWrite);
    final hasVault = _clean(phone) != null || _clean(idNo) != null;
    if (hasVault) {
      _guard.require(Permission.tenantSensitiveWrite);
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Name is required.');
    }
    if (age != null && (age < 0 || age > 120)) {
      throw ArgumentError.value(age, 'age', 'must be between 0 and 120');
    }
    final cleanPhone = _clean(phone) == null ? null : normalizeBdPhone(phone!);
    if (_clean(phone) != null && cleanPhone == null) {
      throw ArgumentError('The phone number is not valid.');
    }
    final cleanId = _clean(idNo) == null ? null : normalizeOtherId(idNo!);
    if (_clean(idNo) != null && cleanId == null) {
      throw ArgumentError('The ID number is not valid.');
    }
    final id = newId();
    await _ctx.transaction(_db, () async {
      final tenant = await _tenant(tenantId);
      _guard.requireInProperty(Permission.tenantWrite, await _propertyOf(tenant));
      final existing = await (_db.select(_db.householdMembers)
            ..where(
              (m) =>
                  m.tenantId.equals(tenantId) & m.orgId.equals(_ctx.orgId) & m.deletedAt.isNull(),
            ))
          .get();
      if (existing.length >= maxMembers) {
        throw StateError('Too many household members.');
      }
      final now = _ctx.now;
      await _db.into(_db.householdMembers).insert(
            HouseholdMembersCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              type: type,
              name: name.trim(),
              relation: Value(_clean(relation)),
              age: Value(age),
              note: Value(_clean(note)),
            ),
          );
      if (hasVault) {
        await _db.into(_db.householdVaults).insert(
              HouseholdVaultsCompanion.insert(
                id: newId(),
                orgId: _ctx.orgId,
                createdAt: now,
                updatedAt: now,
                createdBy: _ctx.userId,
                deviceId: _ctx.deviceId,
                hlc: _ctx.hlc,
                householdMemberId: id,
                phone: Value(cleanPhone),
                idNo: Value(cleanId),
              ),
            );
      }
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'household.add',
        entityType: 'household_member',
        entityId: id,
        // No names, phones or ID numbers in the audit log.
        newValue: jsonEncode({'tenantId': tenantId, 'type': type.name, 'vaultData': hasVault}),
        at: now,
      );
    });
    return id;
  }

  /// Removes a member (kept in the 2-year archive). Owner/Admin only, with a confirmation.
  Future<void> removeMember(
    String memberId, {
    required String reason,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.deleteAny);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is required.');
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.householdRemove,
      entityId: memberId,
    );
    await _ctx.transaction(_db, () async {
      final member = await _member(memberId);
      final vault = await (_db.select(_db.householdVaults)
            ..where(
              (v) =>
                  v.householdMemberId.equals(memberId) &
                  v.orgId.equals(_ctx.orgId) &
                  v.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'household_member',
        entityId: memberId,
        snapshot: {'member': member.toJson(), 'vault': vault?.toJson()},
      );
      await (_db.update(_db.householdMembers)
            ..where((m) => m.id.equals(memberId) & m.orgId.equals(_ctx.orgId)))
          .write(
        HouseholdMembersCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      if (vault != null) {
        await (_db.update(_db.householdVaults)
              ..where((v) => v.id.equals(vault.id) & v.orgId.equals(_ctx.orgId)))
            .write(
          HouseholdVaultsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            hlc: Value(_ctx.hlc),
            syncStatus: Value(SyncStatus.pending),
          ),
        );
      }
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'household.remove',
        entityType: 'household_member',
        entityId: memberId,
        newValue: jsonEncode({'reason': reason.trim()}),
        at: now,
      );
    });
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
