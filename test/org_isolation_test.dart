import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ({String propertyId, String unitId, String tenantId}) ids;
  late String paymentId;
  late String chargeId;
  late String expenseId;
  const intruder = MemberAccess(role: Role.owner);
  const org = 'other-org';

  setUp(() async {
    db = memoryDb();
    ids = await seedTenant(db);
    paymentId = (await paymentsFor(db, ownerAccess).record(tenantId: ids.tenantId, amount: 1000, method: PaymentMethod.cash)).paymentId;
    chargeId = await chargesFor(db, ownerAccess).addCharge(tenantId: ids.tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 500);
    expenseId = await expensesFor(db, ownerAccess).record(
      propertyId: ids.propertyId,
      category: ExpenseCategory.repair,
      amount: 100,
      spentOn: DateTime.utc(2026, 11, 5, 6),
    );
  });
  tearDown(() => db.close());

  test('payments: another organization cannot read, record, edit or cancel', () async {
    final p = paymentsFor(db, intruder, null, org);
    await expectLater(p.record(tenantId: ids.tenantId, amount: 5, method: PaymentMethod.cash), throwsStateError);
    await expectLater(p.ledgerFor(ids.tenantId), throwsStateError);
    await expectLater(p.listForTenant(ids.tenantId), throwsStateError);
    await expectLater(p.getPayment(paymentId), throwsStateError);
    await expectLater(p.balanceAfter(paymentId), throwsStateError);
    await expectLater(
      p.editPayment(paymentId, amount: 1, confirmation: await confirmed(SensitiveAction.paymentEdit, paymentId)),
      throwsStateError,
    );
    await expectLater(
      p.voidPayment(paymentId, reason: 'x', confirmation: await confirmed(SensitiveAction.paymentVoid, paymentId)),
      throwsStateError,
    );
    expect(await p.recent(), isEmpty);
    expect(await p.wasAmended(paymentId), isFalse);
    final unchanged = await db.select(db.payments).getSingle();
    expect(unchanged.amount, 1000);
    expect(unchanged.deletedAt, isNull);
  });

  test('charges: another organization cannot add, list or remove', () async {
    final c = chargesFor(db, intruder, null, org);
    await expectLater(c.addCharge(tenantId: ids.tenantId, month: '2026-11', kind: ChargeKind.gas, amount: 5), throwsStateError);
    await expectLater(c.listForTenant(ids.tenantId), throwsStateError);
    await expectLater(
      c.voidCharge(chargeId, reason: 'x', confirmation: await confirmed(SensitiveAction.chargeVoid, chargeId)),
      throwsStateError,
    );
    expect((await db.select(db.extraCharges).getSingle()).deletedAt, isNull);
  });

  test('expenses: another organization cannot record, list or remove', () async {
    final e = expensesFor(db, intruder, null, org);
    await expectLater(
      e.record(propertyId: ids.propertyId, category: ExpenseCategory.tax, amount: 5, spentOn: DateTime.utc(2026, 11)),
      throwsStateError,
    );
    expect(await e.list(ids.propertyId), isEmpty);
    await expectLater(
      e.voidExpense(expenseId, reason: 'x', confirmation: await confirmed(SensitiveAction.expenseVoid, expenseId)),
      throwsStateError,
    );
    expect((await db.select(db.expenses).getSingle()).deletedAt, isNull);
  });

  test('tenants and units: another organization sees and changes nothing', () async {
    final t = tenantsFor(db, intruder, null, org);
    await expectLater(t.getById(ids.tenantId), throwsStateError);
    await expectLater(t.update(ids.tenantId, name: 'Hacked'), throwsStateError);
    await expectLater(
      t.create(name: 'X', phone: '01711111111', unitId: ids.unitId, leaseStart: DateTime.utc(2026, 9), monthlyRent: 5),
      throwsStateError,
    );
    expect(await t.watchActive().first, isEmpty);
    final p = propertiesFor(db, intruder, null, org);
    await expectLater(p.createUnit(propertyId: ids.propertyId, unitNo: 'Z9', rentAmount: 5), throwsStateError);
    expect(await p.vacantUnits(), isEmpty);
    expect(await p.unitLabels(), isEmpty);
    expect(await p.watchAll().first, isEmpty);
    expect((await db.select(db.tenants).getSingle()).name, 'Karim');
  });

  test('both organizations can use the same unit numbers without clashing', () async {
    final other = propertiesFor(db, intruder, null, org);
    final pid = await other.createProperty(name: 'Rahim Villa', address: 'Dhaka');
    await other.createUnit(propertyId: pid, unitNo: 'A1', rentAmount: 10);
    expect(await propertiesFor(db, ownerAccess).watchAll().first, hasLength(1));
    expect(await other.watchAll().first, hasLength(1));
  });
}
