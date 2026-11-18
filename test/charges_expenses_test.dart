import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';

import 'helpers.dart';


void main() {
  late AppDatabase db;
  late String tenantId;
  late String propertyId;

  setUp(() async {
    db = memoryDb();
    final ids = await seedTenant(db); // rent 10,000 BDT, Sep to Nov = 30,000 BDT owed
    tenantId = ids.tenantId;
    propertyId = ids.propertyId;
  });
  tearDown(() => db.close());

  const owner = ownerAccess;

  group('optional extra charges', () {
    test('a tenant with no extra charges is normal: rent only', () async {
      expect((await paymentsFor(db, owner).ledgerFor(tenantId)).outstanding, 3000000);
      expect(await chargesFor(db, owner).listForTenant(tenantId), isEmpty);
    });

    test('electricity, gas, water and a fine add to what is owed', () async {
      final repo = chargesFor(db, owner);
      await repo.addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.electricity, amount: 85000);
      await repo.addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 120000);
      await repo.addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.water, amount: 30000);
      await repo.addCharge(
        tenantId: tenantId,
        month: '2026-11',
        kind: ChargeKind.fine,
        amount: 50000,
        label: 'Late payment',
      );
      final ledger = await paymentsFor(db, owner).ledgerFor(tenantId);
      expect(ledger.outstanding, 3000000 + 85000 + 120000 + 30000 + 50000);
      expect(ledger.months.last.charged, 1000000 + 285000);
      expect(await repo.listForTenant(tenantId), hasLength(4));
    });

    test('a utility payment reduces what is owed; a deposit does not', () async {
      await chargesFor(db, owner)
          .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 120000);
      final pay = paymentsFor(db, owner);
      await pay.record(
        tenantId: tenantId,
        amount: 120000,
        method: PaymentMethod.cash,
        type: PaymentType.utility,
      );
      expect((await pay.ledgerFor(tenantId)).outstanding, 3000000);
      await pay.record(
        tenantId: tenantId,
        amount: 9999999,
        method: PaymentMethod.cash,
        type: PaymentType.deposit,
      );
      expect((await pay.ledgerFor(tenantId)).outstanding, 3000000);
    });

    test('a fine after the lease month still counts', () async {
      await chargesFor(db, owner).addCharge(
        tenantId: tenantId,
        month: '2027-01',
        kind: ChargeKind.damage,
        amount: 400000,
        note: 'Broken door',
      );
      expect((await paymentsFor(db, owner).ledgerFor(tenantId)).outstanding, 3400000);
    });

    test('invalid charges are rejected and nothing is written', () async {
      final repo = chargesFor(db, owner);
      await expectLater(
        repo.addCharge(tenantId: tenantId, month: '2026-13', kind: ChargeKind.gas, amount: 1),
        throwsArgumentError,
      );
      await expectLater(
        repo.addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 0),
        throwsArgumentError,
      );
      await expectLater(
        repo.addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.other, amount: 100),
        throwsArgumentError,
      );
      await expectLater(
        repo.addCharge(tenantId: 'nope', month: '2026-11', kind: ChargeKind.gas, amount: 100),
        throwsStateError,
      );
      expect(await db.select(db.extraCharges).get(), isEmpty);
    });

    test('owner, admin and manager can add; caretaker and tenant cannot', () async {
      for (final role in [Role.owner, Role.admin, Role.manager]) {
        await chargesFor(db, MemberAccess(role: role))
            .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.water, amount: 100);
      }
      for (final role in [Role.caretaker, Role.tenant]) {
        await expectLater(
          chargesFor(db, MemberAccess(role: role))
              .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.water, amount: 100),
          throwsA(isA<PermissionDenied>()),
        );
      }
    });

    test('a manager scoped to another property cannot add', () async {
      final scoped = MemberAccess(role: Role.manager, propertyScope: {'other'});
      await expectLater(
        chargesFor(db, scoped)
            .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.water, amount: 100),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('removing a charge needs owner/admin and email confirmation, and is audited', () async {
      final id = await chargesFor(db, owner)
          .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 120000);
      await expectLater(
        chargesFor(db, const MemberAccess(role: Role.manager))
            .voidCharge(id, reason: 'wrong', confirmation: await confirmed(SensitiveAction.chargeVoid, id)),
        throwsA(isA<PermissionDenied>()),
      );
      // A token for a different record is refused.
      await expectLater(
        chargesFor(db, owner).voidCharge(
          id,
          reason: 'wrong',
          confirmation: await confirmed(SensitiveAction.chargeVoid, 'some-other-id'),
        ),
        throwsA(isA<ConfirmationException>()),
      );
      await chargesFor(db, owner).voidCharge(
        id,
        reason: 'entered by mistake',
        confirmation: await confirmed(SensitiveAction.chargeVoid, id),
      );
      expect(await db.select(db.deletedArchives).get(), hasLength(1));
      expect((await paymentsFor(db, owner).ledgerFor(tenantId)).outstanding, 3000000);
      expect(await chargesFor(db, owner).listForTenant(tenantId), isEmpty);
      final actions = (await db.select(db.auditLogs).get()).map((l) => l.action);
      expect(actions, containsAll(['charge.add', 'charge.void']));
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('a tenant sees only their own charges', () async {
      await chargesFor(db, owner)
          .addCharge(tenantId: tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 100);
      final own = MemberAccess(role: Role.tenant, linkedTenantId: tenantId);
      final other = MemberAccess(role: Role.tenant, linkedTenantId: 'x');
      expect(await chargesFor(db, own).listForTenant(tenantId), hasLength(1));
      await expectLater(
        chargesFor(db, other).listForTenant(tenantId),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('expense ledger', () {
    final spent = DateTime.utc(2026, 11, 5, 6);

    test('record, list by month, and total', () async {
      final repo = expensesFor(db, owner);
      await repo.record(
        propertyId: propertyId,
        category: ExpenseCategory.repair,
        amount: 250000,
        spentOn: spent,
        note: 'Pump',
      );
      await repo.record(
        propertyId: propertyId,
        category: ExpenseCategory.salary,
        amount: 800000,
        spentOn: spent,
      );
      await repo.record(
        propertyId: propertyId,
        category: ExpenseCategory.tax,
        amount: 100,
        spentOn: DateTime.utc(2026, 10, 15),
      );
      expect(await repo.list(propertyId, month: '2026-11'), hasLength(2));
      expect(await repo.monthTotal(propertyId, '2026-11'), 1050000);
      expect(await repo.monthTotal(propertyId, '2026-10'), 100);
      expect(await repo.list(propertyId), hasLength(3));
    });

    test('Bangladesh month boundary: 18:00 UTC on the 31st belongs to next month', () async {
      final repo = expensesFor(db, owner);
      await repo.record(
        propertyId: propertyId,
        category: ExpenseCategory.other,
        amount: 500,
        spentOn: DateTime.utc(2026, 10, 31, 18),
      );
      expect(await repo.monthTotal(propertyId, '2026-10'), 0);
      expect(await repo.monthTotal(propertyId, '2026-11'), 500);
    });

    test('owner, admin, manager can record; caretaker and tenant cannot', () async {
      for (final role in [Role.owner, Role.admin, Role.manager]) {
        await expensesFor(db, MemberAccess(role: role)).record(
          propertyId: propertyId,
          category: ExpenseCategory.other,
          amount: 1,
          spentOn: spent,
        );
      }
      for (final role in [Role.caretaker, Role.tenant]) {
        await expectLater(
          expensesFor(db, MemberAccess(role: role)).record(
            propertyId: propertyId,
            category: ExpenseCategory.other,
            amount: 1,
            spentOn: spent,
          ),
          throwsA(isA<PermissionDenied>()),
        );
      }
    });

    test('scope, bad amount, unknown property, and caretaker reading are refused', () async {
      await expectLater(
        expensesFor(db, MemberAccess(role: Role.manager, propertyScope: {'other'})).record(
          propertyId: propertyId,
          category: ExpenseCategory.repair,
          amount: 1,
          spentOn: spent,
        ),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        expensesFor(db, owner)
            .record(propertyId: propertyId, category: ExpenseCategory.repair, amount: 0, spentOn: spent),
        throwsArgumentError,
      );
      await expectLater(
        expensesFor(db, owner)
            .record(propertyId: 'nope', category: ExpenseCategory.repair, amount: 5, spentOn: spent),
        throwsStateError,
      );
      await expectLater(
        expensesFor(db, const MemberAccess(role: Role.caretaker)).list(propertyId),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('void needs owner/admin and confirmation; total drops; audit stays valid', () async {
      final repo = expensesFor(db, owner);
      final id = await repo.record(
        propertyId: propertyId,
        category: ExpenseCategory.repair,
        amount: 700,
        spentOn: spent,
      );
      await expectLater(
        expensesFor(db, const MemberAccess(role: Role.manager))
            .voidExpense(id, reason: 'x', confirmation: await confirmed(SensitiveAction.expenseVoid, id)),
        throwsA(isA<PermissionDenied>()),
      );
      // A token meant for another action is refused.
      await expectLater(
        repo.voidExpense(id, reason: 'x', confirmation: await confirmed(SensitiveAction.chargeVoid, id)),
        throwsA(isA<ConfirmationException>()),
      );
      await repo.voidExpense(
        id,
        reason: 'duplicate',
        confirmation: await confirmed(SensitiveAction.expenseVoid, id),
      );
      expect(await repo.monthTotal(propertyId, '2026-11'), 0);
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });
  });
}
