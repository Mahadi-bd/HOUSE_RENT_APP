import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/id_numbers.dart';
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

  const owner = ownerAccess;
  const manager = MemberAccess(role: Role.manager);
  const caretaker = MemberAccess(role: Role.caretaker);

  group('ID number helpers', () {
    test('NID: 10, 13 or 17 digits; Bengali digits and spaces are fine', () {
      expect(normalizeNid('123 456 7890'), '1234567890');
      expect(normalizeNid('১২৩৪৫৬৭৮৯০'), '1234567890');
      expect(normalizeNid('1234567890123'), '1234567890123');
      expect(normalizeNid('12345678901234567'), '12345678901234567');
      for (final bad in ['', '12345', '123456789012', 'ABCDEFGHIJ']) {
        expect(normalizeNid(bad), isNull, reason: bad);
      }
    });

    test('other IDs: 6 to 20 letters or digits', () {
      expect(normalizeOtherId('ab-123456'), 'AB123456');
      expect(normalizeOtherId('123'), isNull);
    });
  });

  group('household', () {
    test('basic members are visible to staff; the count includes the tenant', () async {
      final repo = householdFor(db, manager);
      await repo.addMember(tenantId: tenantId, type: HouseholdType.family, name: 'Rina', relation: 'Wife', age: 30);
      await repo.addMember(tenantId: tenantId, type: HouseholdType.driver, name: 'Salam');
      await repo.addMember(tenantId: tenantId, type: HouseholdType.domesticWorker, name: 'Moni', note: 'Cook');
      final seen = await householdFor(db, caretaker).listBasic(tenantId);
      expect(seen.map((m) => m.name), ['Rina', 'Salam', 'Moni']);
      expect(await householdFor(db, caretaker).memberCount(tenantId), 4);
    });

    test('phone and ID number are vault data: manager without vault access cannot add them', () async {
      await expectLater(
        householdFor(db, manager).addMember(tenantId: tenantId, type: HouseholdType.driver, name: 'Salam', phone: '01711111111'),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        householdFor(db, manager).addMember(tenantId: tenantId, type: HouseholdType.driver, name: 'Salam', idNo: 'AB123456'),
        throwsA(isA<PermissionDenied>()),
      );
      expect(await db.select(db.householdMembers).get(), isEmpty);
    });

    test('vault staff and owner can add and read vault data; others cannot read it', () async {
      final id = await householdFor(db, owner).addMember(
        tenantId: tenantId,
        type: HouseholdType.driver,
        name: 'Salam',
        phone: '017 1111-1111',
        idNo: 'ab-123456',
      );
      final vault = (await householdFor(db, vaultStaff).vaultOf(id))!;
      expect(vault.phone, '8801711111111');
      expect(vault.idNo, 'AB123456');
      for (final a in [manager, caretaker]) {
        await expectLater(householdFor(db, a).vaultOf(id), throwsA(isA<PermissionDenied>()));
      }
      final own = MemberAccess(role: Role.tenant, linkedTenantId: tenantId);
      expect((await householdFor(db, own).vaultOf(id))!.idNo, 'AB123456');
      expect((await householdFor(db, own).listBasic(tenantId)), hasLength(1));
      final other = MemberAccess(role: Role.tenant, linkedTenantId: 'x');
      await expectLater(householdFor(db, other).listBasic(tenantId), throwsA(isA<PermissionDenied>()));
      await expectLater(householdFor(db, other).vaultOf(id), throwsA(isA<PermissionDenied>()));
    });

    test('bad input is refused and nothing is written', () async {
      final repo = householdFor(db, owner);
      await expectLater(repo.addMember(tenantId: tenantId, type: HouseholdType.family, name: ' '), throwsArgumentError);
      await expectLater(repo.addMember(tenantId: tenantId, type: HouseholdType.family, name: 'A', age: 200), throwsArgumentError);
      await expectLater(repo.addMember(tenantId: tenantId, type: HouseholdType.family, name: 'A', phone: '123'), throwsArgumentError);
      await expectLater(repo.addMember(tenantId: tenantId, type: HouseholdType.family, name: 'A', idNo: '12'), throwsArgumentError);
      await expectLater(repo.addMember(tenantId: 'nope', type: HouseholdType.family, name: 'A'), throwsStateError);
      expect(await db.select(db.householdMembers).get(), isEmpty);
      expect(await db.select(db.householdVaults).get(), isEmpty);
    });

    test('no more than 30 people per tenant', () async {
      final repo = householdFor(db, owner);
      for (var i = 0; i < 30; i++) {
        await repo.addMember(tenantId: tenantId, type: HouseholdType.other, name: 'P$i');
      }
      await expectLater(repo.addMember(tenantId: tenantId, type: HouseholdType.other, name: 'Extra'), throwsStateError);
    });

    test('scope and organization are respected', () async {
      final scoped = MemberAccess(role: Role.manager, propertyScope: {'other'});
      await expectLater(
        householdFor(db, scoped).addMember(tenantId: tenantId, type: HouseholdType.family, name: 'A'),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(householdFor(db, scoped).listBasic(tenantId), throwsA(isA<PermissionDenied>()));
      final intruder = householdFor(db, owner, null, 'other-org');
      await expectLater(intruder.listBasic(tenantId), throwsStateError);
      await expectLater(intruder.addMember(tenantId: tenantId, type: HouseholdType.family, name: 'A'), throwsStateError);
    });

    test('removing needs owner/admin and a confirmation; it is archived with vault data and audited', () async {
      final id = await householdFor(db, owner).addMember(
        tenantId: tenantId,
        type: HouseholdType.driver,
        name: 'Salam',
        idNo: 'AB123456',
      );
      await expectLater(
        householdFor(db, manager).removeMember(id, reason: 'x', confirmation: await confirmed(SensitiveAction.householdRemove, id)),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        householdFor(db, owner).removeMember(id, reason: 'x', confirmation: await confirmed(SensitiveAction.paymentVoid, id)),
        throwsA(isA<ConfirmationException>()),
      );
      await householdFor(db, owner).removeMember(id, reason: 'left', confirmation: await confirmed(SensitiveAction.householdRemove, id));
      expect(await householdFor(db, owner).listBasic(tenantId), isEmpty);
      final archive = await db.select(db.deletedArchives).getSingle();
      expect(archive.snapshot, contains('AB123456'));
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('the audit log has no names, phones or ID numbers', () async {
      await householdFor(db, owner).addMember(
        tenantId: tenantId,
        type: HouseholdType.driver,
        name: 'Secret Salam',
        phone: '01711111111',
        idNo: 'AB123456',
      );
      final all = (await db.select(db.auditLogs).get()).map((a) => '${a.newValue}${a.oldValue}').join();
      expect(all, allOf(isNot(contains('Secret')), isNot(contains('01711111111')), isNot(contains('AB123456'))));
    });
  });

  group('tenant vault', () {
    test('owner saves NID, address and emergency contact; vault staff can read; others cannot', () async {
      await vaultFor(db, owner).save(tenantId, nidNo: '1234 5678 90', permanentAddress: 'Village, Khulna', emergencyContact: '01799999999');
      final v = (await vaultFor(db, vaultStaff).get(tenantId))!;
      expect(v.nidNo, '1234567890');
      expect(v.permanentAddress, 'Village, Khulna');
      for (final a in [manager, caretaker]) {
        await expectLater(vaultFor(db, a).get(tenantId), throwsA(isA<PermissionDenied>()));
        await expectLater(vaultFor(db, a).save(tenantId, nidNo: '1234567890'), throwsA(isA<PermissionDenied>()));
      }
      final own = MemberAccess(role: Role.tenant, linkedTenantId: tenantId);
      expect((await vaultFor(db, own).get(tenantId))!.nidNo, '1234567890');
      await expectLater(vaultFor(db, own).save(tenantId, nidNo: '1234567890'), throwsA(isA<PermissionDenied>()));
    });

    test('partial updates keep other fields; an empty text clears a field; only one row per tenant', () async {
      final repo = vaultFor(db, owner);
      await repo.save(tenantId, nidNo: '1234567890', permanentAddress: 'A');
      await repo.save(tenantId, permanentAddress: 'B');
      var v = (await repo.get(tenantId))!;
      expect(v.nidNo, '1234567890');
      expect(v.permanentAddress, 'B');
      await repo.save(tenantId, permanentAddress: '  ');
      v = (await repo.get(tenantId))!;
      expect(v.permanentAddress, isNull);
      expect(await db.select(db.tenantVaults).get(), hasLength(1));
    });

    test('a bad NID is refused', () async {
      await expectLater(vaultFor(db, owner).save(tenantId, nidNo: '12345'), throwsArgumentError);
      expect(await db.select(db.tenantVaults).get(), isEmpty);
    });

    test('scope and organization are respected', () async {
      final scoped = MemberAccess(
        role: Role.manager,
        vaultAccess: true,
        grants: {Permission.tenantSensitiveRead, Permission.tenantSensitiveWrite},
        propertyScope: {'other'},
      );
      await expectLater(vaultFor(db, scoped).save(tenantId, nidNo: '1234567890'), throwsA(isA<PermissionDenied>()));
      final intruder = vaultFor(db, owner, null, 'other-org');
      await expectLater(intruder.get(tenantId), throwsStateError);
      await expectLater(intruder.save(tenantId, nidNo: '1234567890'), throwsStateError);
    });

    test('the audit log names the fields but never their values', () async {
      await vaultFor(db, owner).save(tenantId, nidNo: '1234567890', permanentAddress: 'Secret Village');
      final audit = (await db.select(db.auditLogs).get()).firstWhere((a) => a.action == 'vault.save');
      expect(audit.newValue, allOf(contains('nidNo'), contains('permanentAddress'), isNot(contains('1234567890')), isNot(contains('Secret'))));
    });
  });
}
