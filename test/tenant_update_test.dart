import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late String tenantId;
  setUp(() async {
    db = memoryDb();
    tenantId = (await seedTenant(db)).tenantId;
  });
  tearDown(() => db.close());

  test('name, phone and email can be edited', () async {
    await tenantsFor(db, ownerAccess).update(tenantId, name: ' Karim U ', phone: '+880 1722-222222', email: 'k@example.com');
    final t = await tenantsFor(db, ownerAccess).getById(tenantId);
    expect(t.name, 'Karim U');
    expect(t.phone, '8801722222222');
    expect(t.email, 'k@example.com');
  });

  test('rent can change only before any payment exists', () async {
    final repo = tenantsFor(db, ownerAccess);
    expect(await repo.canEditRent(tenantId), isTrue);
    await repo.update(tenantId, monthlyRent: 1200000, serviceCharge: 50000);
    expect((await repo.getById(tenantId)).monthlyRent, 1200000);
    await paymentsFor(db, ownerAccess).record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
    expect(await repo.canEditRent(tenantId), isFalse);
    await expectLater(repo.update(tenantId, monthlyRent: 5), throwsStateError);
    // Unchanged rent values are not a change.
    await repo.update(tenantId, monthlyRent: 1200000, name: 'Still ok');
  });

  test('lease end can be set and cleared; end before start is refused', () async {
    final repo = tenantsFor(db, ownerAccess);
    await repo.update(tenantId, leaseEnd: DateTime.utc(2027, 1, 1));
    expect((await repo.getById(tenantId)).leaseEnd, isNotNull);
    await repo.update(tenantId, clearLeaseEnd: true);
    expect((await repo.getById(tenantId)).leaseEnd, isNull);
    await expectLater(repo.update(tenantId, leaseEnd: DateTime.utc(2026, 8, 1)), throwsArgumentError);
  });

  test('bad values are refused and nothing changes', () async {
    final repo = tenantsFor(db, ownerAccess);
    await expectLater(repo.update(tenantId, name: ' '), throwsArgumentError);
    await expectLater(repo.update(tenantId, phone: '123'), throwsArgumentError);
    await expectLater(repo.update(tenantId, monthlyRent: 0), throwsArgumentError);
    expect((await repo.getById(tenantId)).name, 'Karim');
  });

  test('who can edit: owner, admin, manager yes; caretaker and tenant no; scope respected', () async {
    for (final role in [Role.owner, Role.admin, Role.manager]) {
      await tenantsFor(db, MemberAccess(role: role)).update(tenantId, name: 'By ${role.name}');
    }
    for (final role in [Role.caretaker, Role.tenant]) {
      await expectLater(
        tenantsFor(db, MemberAccess(role: role)).update(tenantId, name: 'X'),
        throwsA(isA<PermissionDenied>()),
      );
    }
    await expectLater(
      tenantsFor(db, MemberAccess(role: Role.manager, propertyScope: {'other'})).update(tenantId, name: 'X'),
      throwsA(isA<PermissionDenied>()),
    );
  });

  test('the audit log has the money change but no name or phone', () async {
    await tenantsFor(db, ownerAccess).update(tenantId, name: 'Secret Name', phone: '01733333333', monthlyRent: 900000);
    final audit = (await db.select(db.auditLogs).get()).firstWhere((a) => a.action == 'tenant.update');
    expect('${audit.oldValue}${audit.newValue}', allOf(contains('900000'), isNot(contains('Secret')), isNot(contains('01733333333'))));
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });
}
