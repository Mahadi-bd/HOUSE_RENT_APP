import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// A vacant unit together with its property name, for pickers.
class UnitChoice {
  /// Creates a choice.
  const UnitChoice(this.unit, this.propertyName);

  /// The unit.
  final Unit unit;

  /// Name of the property it belongs to.
  final String propertyName;
}

/// Properties and their units, with permission checks and audit records.
class PropertiesRepository {
  /// Creates the repository.
  PropertiesRepository(this._db, this._guard, this._ctx);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;

  /// Properties this member may see (respecting the property scope).
  Stream<List<Property>> watchAll() {
    _guard.require(Permission.tenantBasicRead);
    final query = _db.select(_db.properties)
      ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);
    return query.watch().map(
          (rows) => [for (final p in rows) if (_guard.access!.canAccessProperty(p.id)) p],
        );
  }

  /// Creates a property and returns its id. Owner/Admin only.
  Future<String> createProperty({
    required String name,
    required String address,
    String type = 'building',
  }) async {
    _guard.require(Permission.propertyWrite);
    if (name.trim().isEmpty || address.trim().isEmpty) {
      throw ArgumentError('Name and address are required.');
    }
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      await _db.into(_db.properties).insert(
            PropertiesCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              name: name.trim(),
              address: address.trim(),
              type: Value(type),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'property.create',
        entityType: 'property',
        entityId: id,
        newValue: jsonEncode({'name': name.trim(), 'type': type}),
        at: now,
      );
    });
    return id;
  }

  /// Creates a unit (flat or room). [rentAmount] is in poisha and must be above zero.
  Future<String> createUnit({
    required String propertyId,
    required String unitNo,
    required int rentAmount,
    String? floor,
  }) async {
    _guard.requireInProperty(Permission.propertyWrite, propertyId);
    if (unitNo.trim().isEmpty) {
      throw ArgumentError('Unit number is required.');
    }
    if (rentAmount <= 0) {
      throw ArgumentError.value(rentAmount, 'rentAmount', 'must be above zero (poisha)');
    }
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      final property = await (_db.select(_db.properties)
            ..where(
              (p) => p.id.equals(propertyId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (property == null) {
        throw StateError('Property not found.');
      }
      await _db.into(_db.units).insert(
            UnitsCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              propertyId: propertyId,
              unitNo: unitNo.trim(),
              rentAmount: rentAmount,
              floor: Value(floor),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'unit.create',
        entityType: 'unit',
        entityId: id,
        newValue: jsonEncode({'propertyId': propertyId, 'unitNo': unitNo.trim()}),
        at: now,
      );
    });
    return id;
  }

  /// Units of [propertyId] this member may see.
  Stream<List<Unit>> watchUnits(String propertyId) {
    _guard.requireInProperty(Permission.tenantBasicRead, propertyId);
    final query = _db.select(_db.units)
      ..where(
        (u) => u.orgId.equals(_ctx.orgId) & u.propertyId.equals(propertyId) & u.deletedAt.isNull(),
      )
      ..orderBy([(u) => OrderingTerm.asc(u.unitNo)]);
    return query.watch();
  }

  /// Vacant units this member may put a tenant in (needs tenant write permission and scope).
  Future<List<UnitChoice>> vacantUnits() async {
    _guard.require(Permission.tenantWrite);
    final units = await (_db.select(_db.units)
          ..where(
            (u) =>
                u.orgId.equals(_ctx.orgId) &
                u.deletedAt.isNull() &
                u.status.equalsValue(UnitStatus.vacant),
          ))
        .get();
    final properties = await (_db.select(_db.properties)
          ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull()))
        .get();
    final names = {for (final p in properties) p.id: p.name};
    final choices = [
      for (final u in units)
        if (names.containsKey(u.propertyId) && _guard.access!.canAccessProperty(u.propertyId))
          UnitChoice(u, names[u.propertyId]!),
    ]..sort((a, b) {
        final byProperty = a.propertyName.compareTo(b.propertyName);
        return byProperty != 0 ? byProperty : a.unit.unitNo.compareTo(b.unit.unitNo);
      });
    return choices;
  }

  /// Short labels such as "Rahim Villa A1" for every unit this member may see, by unit id.
  Future<Map<String, String>> unitLabels() async {
    _guard.require(Permission.tenantBasicRead);
    final units = await (_db.select(_db.units)..where((u) => u.orgId.equals(_ctx.orgId))).get();
    final properties = await (_db.select(_db.properties)
          ..where((p) => p.orgId.equals(_ctx.orgId)))
        .get();
    final names = {for (final p in properties) p.id: p.name};
    return {
      for (final u in units)
        if (names.containsKey(u.propertyId) && _guard.access!.canAccessProperty(u.propertyId))
          u.id: '${names[u.propertyId]} ${u.unitNo}',
    };
  }
}
