import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('properties and units', () {
    test('owner creates a property and unit; both are audited', () async {
      final ids = await seedTenant(db);
      expect(await db.select(db.properties).get(), hasLength(1));
      expect(await db.select(db.units).get(), hasLength(1));
      expect(ids.tenantId, isNotEmpty);
      final actions = (await db.select(db.auditLogs).get()).map((a) => a.action).toList();
      expect(actions, containsAll(['property.create', 'unit.create', 'tenant.create']));
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('manager, caretaker and tenant cannot create properties or units', () async {
      for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
        final repo = propertiesFor(db, MemberAccess(role: role));
        await expectLater(
          repo.createProperty(name: 'X', address: 'Y'),
          throwsA(isA<PermissionDenied>()),
        );
      }
    });

    test('invalid input is rejected and nothing is written', () async {
      final repo = propertiesFor(db, ownerAccess);
      await expectLater(repo.createProperty(name: ' ', address: 'Y'), throwsArgumentError);
      final pid = await repo.createProperty(name: 'A', address: 'B');
      await expectLater(
        repo.createUnit(propertyId: pid, unitNo: 'A1', rentAmount: 0),
        throwsArgumentError,
      );
      expect(await db.select(db.units).get(), isEmpty);
    });

    test('a scoped manager sees only the properties in scope', () async {
      final repo = propertiesFor(db, ownerAccess);
      final p1 = await repo.createProperty(name: 'One', address: 'a');
      await repo.createProperty(name: 'Two', address: 'b');
      final scoped = propertiesFor(db, MemberAccess(role: Role.manager, propertyScope: {p1}));
      final visible = await scoped.watchAll().first;
      expect(visible.map((p) => p.name), ['One']);
    });
  });

  group('tenants', () {
    test('creating a tenant marks the unit occupied', () async {
      final ids = await seedTenant(db);
      final unit = await (db.select(db.units)..where((u) => u.id.equals(ids.unitId))).getSingle();
      expect(unit.status, UnitStatus.occupied);
    });

    test('a unit cannot get a second active tenant', () async {
      final ids = await seedTenant(db);
      await expectLater(
        tenantsFor(db, ownerAccess).create(
          name: 'Other',
          phone: '01722222222',
          unitId: ids.unitId,
          leaseStart: DateTime.utc(2026, 10),
          monthlyRent: 1000000,
        ),
        throwsStateError,
      );
    });

    test('bad phone, rent, or lease dates are rejected', () async {
      final props = propertiesFor(db, ownerAccess);
      final pid = await props.createProperty(name: 'A', address: 'B');
      final uid = await props.createUnit(propertyId: pid, unitNo: 'A1', rentAmount: 500000);
      final repo = tenantsFor(db, ownerAccess);
      Future<String> make({String phone = '01711111111', int rent = 500000, DateTime? end}) =>
          repo.create(
            name: 'T',
            phone: phone,
            unitId: uid,
            leaseStart: DateTime.utc(2026, 9),
            monthlyRent: rent,
            leaseEnd: end,
          );
      await expectLater(make(phone: '123'), throwsArgumentError);
      await expectLater(make(rent: 0), throwsArgumentError);
      await expectLater(make(end: DateTime.utc(2026, 8)), throwsArgumentError);
      expect(await db.select(db.tenants).get(), isEmpty);
    });

    test('a manager scoped to another property cannot add a tenant', () async {
      final props = propertiesFor(db, ownerAccess);
      final pid = await props.createProperty(name: 'A', address: 'B');
      final uid = await props.createUnit(propertyId: pid, unitNo: 'A1', rentAmount: 500000);
      final scoped = tenantsFor(db, MemberAccess(role: Role.manager, propertyScope: {'other'}));
      await expectLater(
        scoped.create(
          name: 'T',
          phone: '01711111111',
          unitId: uid,
          leaseStart: DateTime.utc(2026, 9),
          monthlyRent: 500000,
        ),
        throwsA(isA<PermissionDenied>()),
      );
      expect(await db.select(db.tenants).get(), isEmpty);
    });

    test('the audit log never contains the phone number', () async {
      await seedTenant(db);
      final all = (await db.select(db.auditLogs).get()).map((a) => '${a.newValue}${a.oldValue}');
      expect(all.any((v) => v.contains('01711111111')), isFalse);
    });

    test('reading needs permission; delete needs owner/admin and a real confirmation', () async {
      final ids = await seedTenant(db);
      expect(
        () => tenantsFor(db, const MemberAccess(role: Role.tenant)).watchActive(),
        throwsA(isA<PermissionDenied>()),
      );
      for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
        await expectLater(
          tenantsFor(db, MemberAccess(role: role)).softDelete(
            ids.tenantId,
            confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId),
          ),
          throwsA(isA<PermissionDenied>()),
        );
      }
      await tenantsFor(db, ownerAccess).softDelete(
        ids.tenantId,
        confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId),
      );
      expect(await tenantsFor(db, ownerAccess).watchActive().first, isEmpty);
    });
  });
}
