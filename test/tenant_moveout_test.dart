import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ({String propertyId, String unitId, String tenantId}) ids;

  setUp(() async {
    db = memoryDb();
    ids = await seedTenant(db);
  });
  tearDown(() => db.close());

  Future<void> moveOut(String tenantId, {String org = 'org'}) async =>
      tenantsFor(db, ownerAccess, null, org).softDelete(
        tenantId,
        confirmation: await confirmed(SensitiveAction.tenantDelete, tenantId),
      );

  Future<Unit> unit() => (db.select(db.units)..where((u) => u.id.equals(ids.unitId))).getSingle();
  Future<Tenant> tenant(String id) => (db.select(db.tenants)..where((t) => t.id.equals(id))).getSingle();

  test('normal move-out: tenant hidden and moved out, unit vacant, archived and audited', () async {
    await moveOut(ids.tenantId);
    final row = await tenant(ids.tenantId);
    expect(row.deletedAt, isNotNull);
    expect(row.status, TenantStatus.vacated);
    expect(row.syncStatus, SyncStatus.pending);
    expect(row.hlc, isNot('1'));
    expect((await unit()).status, UnitStatus.vacant);
    expect(await tenantsFor(db, ownerAccess).watchActive().first, isEmpty);

    final archive = await db.select(db.deletedArchives).getSingle();
    expect(archive.entityType, 'tenant');
    expect(archive.entityId, ids.tenantId);
    expect(archive.snapshot, contains('Karim'));
    expect(archive.purgeAfter.difference(archive.deletedAt), ArchiveWriter.retention);

    final audit = (await db.select(db.auditLogs).get()).where((a) => a.action == 'tenant.delete').single;
    expect(audit.newValue, contains('"unitFreed":true'));
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });

  test('a vacated unit can take a new tenant', () async {
    await moveOut(ids.tenantId);
    final again = await tenantsFor(db, ownerAccess).create(
      name: 'Next',
      phone: '01799999999',
      unitId: ids.unitId,
      leaseStart: DateTime.utc(2026, 11),
      monthlyRent: 1000000,
    );
    expect(again, isNotEmpty);
    expect((await unit()).status, UnitStatus.occupied);
  });

  test('the unit stays occupied while another active tenant lives there', () async {
    final now = DateTime.utc(2026, 11);
    await db.into(db.tenants).insert(
          TenantsCompanion.insert(
            id: 'second', orgId: 'org', createdAt: now, updatedAt: now, createdBy: 'u',
            deviceId: 'd', hlc: '1', name: 'Second', phone: '01722222222', unitId: ids.unitId,
            leaseStart: now, monthlyRent: 1,
          ),
        );
    await moveOut(ids.tenantId);
    expect((await unit()).status, UnitStatus.occupied);
    final audit = (await db.select(db.auditLogs).get()).where((a) => a.action == 'tenant.delete').single;
    expect(audit.newValue, contains('"unitFreed":false'));
    expect((await tenant('second')).deletedAt, isNull);
  });

  test('a tenant of another organization cannot be moved out', () async {
    await expectLater(moveOut(ids.tenantId, org: 'other-org'), throwsStateError);
    expect((await tenant(ids.tenantId)).deletedAt, isNull);
    expect((await unit()).status, UnitStatus.occupied);
    expect(await db.select(db.deletedArchives).get(), isEmpty);
  });

  test('a missing or already moved-out tenant is refused', () async {
    await expectLater(moveOut('nope'), throwsStateError);
    await moveOut(ids.tenantId);
    await expectLater(moveOut(ids.tenantId), throwsStateError);
  });

  test('a failure in the middle leaves nothing half-done', () async {
    await db.customStatement('DROP TABLE deleted_archives');
    await expectLater(moveOut(ids.tenantId), throwsA(anything));
    expect((await tenant(ids.tenantId)).deletedAt, isNull);
    expect((await tenant(ids.tenantId)).status, TenantStatus.active);
    expect((await unit()).status, UnitStatus.occupied);
    final actions = (await db.select(db.auditLogs).get()).map((a) => a.action);
    expect(actions, isNot(contains('tenant.delete')));
  });

  test('payments of a moved-out tenant are kept', () async {
    await paymentsFor(db, ownerAccess).record(tenantId: ids.tenantId, amount: 100, method: PaymentMethod.cash);
    await moveOut(ids.tenantId);
    expect(await db.select(db.payments).get(), hasLength(1));
  });
}
