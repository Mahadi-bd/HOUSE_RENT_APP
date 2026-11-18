import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_repository.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late MemoryKeyValueStore keys;
  late ({String propertyId, String unitId, String tenantId}) ids;

  setUp(() async {
    db = memoryDb();
    root = Directory.systemTemp.createTempSync('rent_solution_archive_');
    keys = MemoryKeyValueStore();
    ids = await seedTenant(db);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  const owner = ownerAccess;

  test('only owner or admin can see, restore or purge', () async {
    for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
      final repo = archiveFor(db, MemberAccess(role: role), root);
      await expectLater(repo.list(), throwsA(isA<PermissionDenied>()));
      await expectLater(repo.restore('x'), throwsA(isA<PermissionDenied>()));
      await expectLater(repo.purgeExpired(), throwsA(isA<PermissionDenied>()));
    }
  });

  test('a cancelled payment can be restored; the balance comes back and the entry leaves the list', () async {
    final pay = paymentsFor(db, owner);
    final r = await pay.record(tenantId: ids.tenantId, amount: 1000000, method: PaymentMethod.cash);
    await pay.voidPayment(r.paymentId, reason: 'typo', confirmation: await confirmed(SensitiveAction.paymentVoid, r.paymentId));
    expect((await pay.ledgerFor(ids.tenantId)).outstanding, 3000000);

    final repo = archiveFor(db, owner, root);
    final entry = (await repo.list()).single;
    expect(entry.entityType, 'payment');
    await repo.restore(entry.id);
    expect((await pay.ledgerFor(ids.tenantId)).outstanding, 2000000);
    expect(await repo.list(), isEmpty);
    expect((await db.select(db.deletedArchives).getSingle()).restoredAt, isNotNull);
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    await expectLater(repo.restore(entry.id), throwsStateError);
  });

  test('a restored payment is refused when its TrxID was used again', () async {
    final pay = paymentsFor(db, owner);
    final a = await pay.record(tenantId: ids.tenantId, amount: 1000, method: PaymentMethod.bkash, trxId: 'SAME1234');
    await pay.voidPayment(a.paymentId, reason: 'x', confirmation: await confirmed(SensitiveAction.paymentVoid, a.paymentId));
    await pay.record(tenantId: ids.tenantId, amount: 1000, method: PaymentMethod.bkash, trxId: 'SAME1234');
    final repo = archiveFor(db, owner, root);
    await expectLater(repo.restore((await repo.list()).single.id), throwsStateError);
  });

  test('a moved-out tenant can be restored; the unit is occupied again', () async {
    await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
    final repo = archiveFor(db, owner, root);
    await repo.restore((await repo.list()).single.id);
    final t = await tenantsFor(db, owner).getById(ids.tenantId);
    expect(t.status, TenantStatus.active);
    final unit = await (db.select(db.units)..where((u) => u.id.equals(ids.unitId))).getSingle();
    expect(unit.status, UnitStatus.occupied);
  });

  test('a tenant cannot come back into a unit that has a new tenant', () async {
    await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
    await tenantsFor(db, owner).create(name: 'New', phone: '01788888888', unitId: ids.unitId, leaseStart: DateTime.utc(2026, 11), monthlyRent: 1);
    final repo = archiveFor(db, owner, root);
    await expectLater(repo.restore((await repo.list()).single.id), throwsStateError);
  });

  test('another organization cannot restore', () async {
    await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
    final entry = (await archiveFor(db, owner, root).list()).single;
    await expectLater(archiveFor(db, owner, root, orgId: 'other-org').restore(entry.id), throwsStateError);
    expect(await archiveFor(db, owner, root, orgId: 'other-org').list(), isEmpty);
  });

  test('purge: nothing happens before 2 years; after 2 years data is gone for good', () async {
    final pay = paymentsFor(db, owner);
    final r = await pay.record(tenantId: ids.tenantId, amount: 500, method: PaymentMethod.cash);
    await pay.voidPayment(r.paymentId, reason: 'x', confirmation: await confirmed(SensitiveAction.paymentVoid, r.paymentId));
    expect(await archiveFor(db, owner, root).purgeExpired(), 0);
    expect(await db.select(db.payments).get(), hasLength(1));

    final later = testNow.add(const Duration(days: 731));
    expect(await archiveFor(db, owner, root, now: later).purgeExpired(), 1);
    expect(await db.select(db.payments).get(), isEmpty);
    expect(await db.select(db.deletedArchives).get(), isEmpty);
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });

  test('purging a tenant leaves a stub and removes personal data, files and archive snapshots', () async {
    await vaultFor(db, owner).save(ids.tenantId, nidNo: '1234567890', permanentAddress: 'Secret Village');
    final memberId = await householdFor(db, owner).addMember(tenantId: ids.tenantId, type: HouseholdType.driver, name: 'Secret Driver', idNo: 'AB123456');
    final docId = await documentsFor(db, owner, root, keyStore: keys)
        .store(tenantId: ids.tenantId, type: DocumentType.nid, bytes: Uint8List.fromList(List.filled(100, 5)), extension: 'jpg');
    final file = File('${root.path}/${(await db.select(db.documents).getSingle()).localPath}');
    expect(file.existsSync(), isTrue);
    await paymentsFor(db, owner).record(tenantId: ids.tenantId, amount: 700, method: PaymentMethod.cash);
    await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));

    final later = testNow.add(const Duration(days: 731));
    final purged = await archiveFor(db, owner, root, now: later).purgeExpired();
    expect(purged, 1);
    final tenant = await (db.select(db.tenants)..where((t) => t.id.equals(ids.tenantId))).getSingle();
    expect(tenant.name, ArchiveRepository.erasedName);
    expect(tenant.phone, '');
    expect(await db.select(db.tenantVaults).get(), isEmpty);
    expect(await db.select(db.householdMembers).get(), isEmpty);
    expect(await db.select(db.householdVaults).get(), isEmpty);
    expect(await db.select(db.documents).get(), isEmpty);
    expect(file.existsSync(), isFalse);
    expect(await db.select(db.deletedArchives).get(), isEmpty);
    expect(await db.select(db.payments).get(), hasLength(1));
    expect(memberId, isNotEmpty);
    expect(docId, isNotEmpty);
    // A stub cannot be restored.
    expect((await db.select(db.deletedArchives).get()), isEmpty);
  });
}
