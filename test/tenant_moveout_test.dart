import 'package:drift/drift.dart' hide isNotNull, isNull;
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

  Future<void> moveOut(String tenantId, {String org = 'org'}) async => tenantsFor(db, ownerAccess, null, org)
      .softDelete(tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, tenantId));

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
}
