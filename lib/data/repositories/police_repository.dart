import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// One person in the home, as printed on the police form.
class PoliceMember {
  /// Creates a member line.
  const PoliceMember({
    required this.name,
    required this.typeName,
    this.relation,
    this.age,
    this.phone,
    this.idNo,
  });

  /// Name.
  final String name;

  /// household type name (family, driver...).
  final String typeName;

  /// Relation to the tenant.
  final String? relation;

  /// Age.
  final int? age;

  /// Phone (private data).
  final String? phone;

  /// ID number (private data).
  final String? idNo;
}

/// Everything on the tenant information form for the police.
class PoliceFormData {
  /// Creates the form data.
  const PoliceFormData({
    required this.tenantName,
    required this.tenantPhone,
    required this.unitLabel,
    required this.leaseStart,
    required this.members,
    this.tenantEmail,
    this.nidNo,
    this.permanentAddress,
    this.emergencyContact,
    this.leaseEnd,
    this.orgName,
    this.ownerName,
    this.orgAddress,
    this.orgPhone,
  });

  /// Tenant name.
  final String tenantName;

  /// Tenant phone.
  final String tenantPhone;

  /// Tenant email.
  final String? tenantEmail;

  /// NID number.
  final String? nidNo;

  /// Permanent address.
  final String? permanentAddress;

  /// Emergency contact.
  final String? emergencyContact;

  /// Property and unit.
  final String unitLabel;

  /// Lease start.
  final DateTime leaseStart;

  /// Lease end.
  final DateTime? leaseEnd;

  /// People in the home.
  final List<PoliceMember> members;

  /// Business name.
  final String? orgName;

  /// Owner name.
  final String? ownerName;

  /// Business address.
  final String? orgAddress;

  /// Business phone.
  final String? orgPhone;
}

/// Builds the police information form and keeps the consent log. Owner/Admin only.
class PoliceFormRepository {
  /// Creates the repository.
  PoliceFormRepository(this._db, this._guard, this._ctx);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;

  /// Collects the data for [tenantId]. Needs police-share permission and vault access.
  Future<PoliceFormData> prepare(String tenantId) async {
    _guard.require(Permission.policeShare);
    _guard.requireVaultRead(tenantId);
    final tenant = await (_db.select(_db.tenants)
          ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    final unit = await (_db.select(_db.units)
          ..where((u) => u.id.equals(tenant.unitId) & u.orgId.equals(_ctx.orgId)))
        .getSingle();
    _guard.requireInProperty(Permission.policeShare, unit.propertyId);
    final property = await (_db.select(_db.properties)
          ..where((p) => p.id.equals(unit.propertyId) & p.orgId.equals(_ctx.orgId)))
        .getSingleOrNull();
    final vault = await (_db.select(_db.tenantVaults)
          ..where((v) => v.tenantId.equals(tenantId) & v.orgId.equals(_ctx.orgId) & v.deletedAt.isNull()))
        .getSingleOrNull();
    final members = await (_db.select(_db.householdMembers)
          ..where((m) => m.tenantId.equals(tenantId) & m.orgId.equals(_ctx.orgId) & m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
    final lines = <PoliceMember>[];
    for (final m in members) {
      final v = await (_db.select(_db.householdVaults)
            ..where(
              (x) => x.householdMemberId.equals(m.id) & x.orgId.equals(_ctx.orgId) & x.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      lines.add(
        PoliceMember(
          name: m.name,
          typeName: m.type.name,
          relation: m.relation,
          age: m.age,
          phone: v?.phone,
          idNo: v?.idNo,
        ),
      );
    }
    final profile = await (_db.select(_db.orgProfiles)
          ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull()))
        .getSingleOrNull();
    return PoliceFormData(
      tenantName: tenant.name,
      tenantPhone: tenant.phone,
      tenantEmail: tenant.email,
      nidNo: vault?.nidNo,
      permanentAddress: vault?.permanentAddress,
      emergencyContact: vault?.emergencyContact,
      unitLabel: '${property?.name ?? ''} ${unit.unitNo}'.trim(),
      leaseStart: tenant.leaseStart,
      leaseEnd: tenant.leaseEnd,
      members: lines,
      orgName: profile?.displayName,
      ownerName: profile?.ownerName,
      orgAddress: profile?.address,
      orgPhone: profile?.phone,
    );
  }

  /// Records that the form was shared, with the tenant's consent. Refuses without consent.
  /// The log never contains the tenant's data.
  Future<String> recordShare({
    required String tenantId,
    required String channel,
    required bool consentConfirmed,
  }) async {
    _guard.require(Permission.policeShare);
    if (!consentConfirmed) {
      throw ArgumentError('The tenant\'s consent must be confirmed first.');
    }
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      final tenant = await (_db.select(_db.tenants)
            ..where((t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (tenant == null) {
        throw StateError('Tenant not found.');
      }
      await _db.into(_db.policeShares).insert(
            PoliceSharesCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              sharedBy: _ctx.userId,
              sharedAt: now,
              channel: channel,
              consentConfirmed: true,
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'police.share',
        entityType: 'tenant',
        entityId: tenantId,
        newValue: jsonEncode({'channel': channel, 'consent': true}),
        at: now,
      );
    });
    return id;
  }

  /// The consent log of a tenant, newest first.
  Future<List<PoliceShare>> log(String tenantId) async {
    _guard.require(Permission.policeShare);
    return (_db.select(_db.policeShares)
          ..where((s) => s.tenantId.equals(tenantId) & s.orgId.equals(_ctx.orgId))
          ..orderBy([(s) => OrderingTerm.desc(s.sharedAt)]))
        .get();
  }
}
