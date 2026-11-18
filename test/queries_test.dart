import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('vacant units: only vacant ones, with property name, respecting scope', () async {
    final props = propertiesFor(db, ownerAccess);
    final p1 = await props.createProperty(name: 'Alpha', address: 'a');
    final p2 = await props.createProperty(name: 'Beta', address: 'b');
    final u1 = await props.createUnit(propertyId: p1, unitNo: 'A1', rentAmount: 100);
    await props.createUnit(propertyId: p1, unitNo: 'A2', rentAmount: 100);
    await props.createUnit(propertyId: p2, unitNo: 'B1', rentAmount: 100);
    await tenantsFor(db, ownerAccess).create(
      name: 'T',
      phone: '01711111111',
      unitId: u1,
      leaseStart: DateTime.utc(2026, 9),
      monthlyRent: 100,
    );
    final all = await propertiesFor(db, ownerAccess).vacantUnits();
    expect(all.map((c) => '${c.propertyName} ${c.unit.unitNo}'), ['Alpha A2', 'Beta B1']);
    final scoped = MemberAccess(role: Role.manager, propertyScope: {p2});
    expect((await propertiesFor(db, scoped).vacantUnits()).map((c) => c.unit.unitNo), ['B1']);
    await expectLater(
      propertiesFor(db, const MemberAccess(role: Role.caretaker)).vacantUnits(),
      throwsA(isA<PermissionDenied>()),
    );
  });

  test('tenant getById: staff in scope yes, other scope no, tenant own only', () async {
    final ids = await seedTenant(db);
    expect((await tenantsFor(db, ownerAccess).getById(ids.tenantId)).name, 'Karim');
    expect(
      (await tenantsFor(db, const MemberAccess(role: Role.caretaker)).getById(ids.tenantId)).id,
      ids.tenantId,
    );
    await expectLater(
      tenantsFor(db, MemberAccess(role: Role.manager, propertyScope: {'other'})).getById(ids.tenantId),
      throwsA(isA<PermissionDenied>()),
    );
    final own = MemberAccess(role: Role.tenant, linkedTenantId: ids.tenantId);
    final other = MemberAccess(role: Role.tenant, linkedTenantId: 'x');
    expect((await tenantsFor(db, own).getById(ids.tenantId)).id, ids.tenantId);
    await expectLater(
      tenantsFor(db, other).getById(ids.tenantId),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(tenantsFor(db, ownerAccess).getById('nope'), throwsStateError);
  });

  test('recent payments: newest first, scope respected, tenant role refused', () async {
    final a = await seedTenant(db);
    final b = await seedTenant(db, unitNo: 'A2', propertyId: a.propertyId);
    final p2 = await propertiesFor(db, ownerAccess).createProperty(name: 'Other', address: 'z');
    final u3 = await propertiesFor(db, ownerAccess)
        .createUnit(propertyId: p2, unitNo: 'Z1', rentAmount: 100);
    final t3 = await tenantsFor(db, ownerAccess).create(
      name: 'Far',
      phone: '01733333333',
      unitId: u3,
      leaseStart: DateTime.utc(2026, 9),
      monthlyRent: 100,
    );
    final pay = paymentsFor(db, ownerAccess);
    await pay.record(tenantId: a.tenantId, amount: 100, method: PaymentMethod.cash);
    await pay.record(tenantId: b.tenantId, amount: 200, method: PaymentMethod.cash);
    await pay.record(tenantId: t3, amount: 50, method: PaymentMethod.cash);

    expect(await pay.recent(), hasLength(3));
    final scoped = MemberAccess(role: Role.manager, propertyScope: {a.propertyId});
    final visible = await paymentsFor(db, scoped).recent();
    expect(visible.map((p) => p.amount).toSet(), {100, 200});
    expect(await paymentsFor(db, ownerAccess).recent(limit: 1), hasLength(1));
    await expectLater(
      paymentsFor(db, const MemberAccess(role: Role.tenant)).recent(),
      throwsA(isA<PermissionDenied>()),
    );
  });
}
