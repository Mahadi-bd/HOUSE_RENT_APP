import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/domain/money/ledger.dart';
import 'package:rent_solution/domain/money/payment_classifier.dart';

import 'helpers.dart';

void main() {
  const charges = [MonthCharge('2026-09', 1000000), MonthCharge('2026-10', 1000000), MonthCharge('2026-11', 1000000)];

  group('classifyPayment', () {
    PaymentClassification c(int amount, List<int> prior, {PaymentType type = PaymentType.rent, bool counts = true}) =>
        classifyPayment(
          charges: charges,
          priorPayments: prior,
          amount: amount,
          type: type,
          countsAgainstDues: counts,
          currentMonth: '2026-11',
        );

    test('partial, exact and advance', () {
      expect(c(1000000, []).status, PaymentStatus.partial);
      expect(c(1000000, []).type, PaymentType.partial);
      expect(c(1000000, []).forMonth, '2026-09');
      expect(c(3000000, []).status, PaymentStatus.paid);
      expect(c(3000000, []).type, PaymentType.rent);
      expect(c(100, [3000000]).status, PaymentStatus.advance);
      expect(c(100, [3000000]).type, PaymentType.advance);
      expect(c(100, [3000000]).forMonth, '2026-12');
      expect(c(3500000, []).status, PaymentStatus.advance);
    });

    test('later months when earlier ones are paid', () {
      expect(c(500000, [1000000]).forMonth, '2026-10');
    });

    test('a deposit is just paid for the current month', () {
      final r = c(9999999, [], type: PaymentType.deposit, counts: false);
      expect(r.status, PaymentStatus.paid);
      expect(r.type, PaymentType.deposit);
      expect(r.forMonth, '2026-11');
    });

    test('utility payments keep their type', () {
      expect(c(100, [], type: PaymentType.utility).type, PaymentType.utility);
    });
  });

  group('after an edit or a cancellation the labels follow the numbers', () {
    late AppDatabase db;
    late String tenantId;
    setUp(() async {
      db = memoryDb();
      tenantId = (await seedTenant(db)).tenantId;
    });
    tearDown(() => db.close());

    Future<Map<String, Payment>> byReceipt() async =>
        {for (final p in await db.select(db.payments).get()) p.receiptNo: p};

    test('lowering a payment turns "paid" into "partial"', () async {
      final repo = paymentsFor(db, ownerAccess);
      final r = await repo.record(tenantId: tenantId, amount: 3000000, method: PaymentMethod.cash);
      expect((await byReceipt())[r.receiptNo]!.status, PaymentStatus.paid);
      await repo.editPayment(r.paymentId, amount: 1000000, confirmation: await confirmed(SensitiveAction.paymentEdit, r.paymentId));
      final p = (await byReceipt())[r.receiptNo]!;
      expect(p.status, PaymentStatus.partial);
      expect(p.type, PaymentType.partial);
      expect(p.forMonth, '2026-09');
      expect(p.receiptNo, r.receiptNo);
    });

    test('raising a payment beyond the debt turns it into advance', () async {
      final repo = paymentsFor(db, ownerAccess);
      final r = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      await repo.editPayment(r.paymentId, amount: 3200000, confirmation: await confirmed(SensitiveAction.paymentEdit, r.paymentId));
      expect((await byReceipt())[r.receiptNo]!.status, PaymentStatus.advance);
    });

    test('cancelling a middle payment relabels the later ones', () async {
      final repo = paymentsFor(db, ownerAccess);
      final a = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      final b = await repo.record(tenantId: tenantId, amount: 2000000, method: PaymentMethod.cash);
      final c = await repo.record(tenantId: tenantId, amount: 500000, method: PaymentMethod.cash);
      expect((await byReceipt())[c.receiptNo]!.status, PaymentStatus.advance);

      await repo.voidPayment(b.paymentId, reason: 'duplicate', confirmation: await confirmed(SensitiveAction.paymentVoid, b.paymentId));
      final labels = await byReceipt();
      expect(labels[a.receiptNo]!.status, PaymentStatus.partial);
      expect(labels[c.receiptNo]!.status, PaymentStatus.partial);
      expect(labels[c.receiptNo]!.type, PaymentType.partial);
      expect((await repo.ledgerFor(tenantId)).outstanding, 1500000);
    });

    test('the audit log keeps old and new values and how many labels changed', () async {
      final repo = paymentsFor(db, ownerAccess);
      final r = await repo.record(tenantId: tenantId, amount: 3000000, method: PaymentMethod.cash);
      await repo.editPayment(r.paymentId, amount: 1000000, confirmation: await confirmed(SensitiveAction.paymentEdit, r.paymentId));
      final edit = (await db.select(db.auditLogs).get()).firstWhere((l) => l.action == 'payment.edit');
      expect(edit.oldValue, allOf(contains('3000000'), contains('"status":"paid"')));
      expect(edit.newValue, allOf(contains('1000000'), contains('relabeledPayments')));
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('receipt balance is the balance at that time and a corrected payment is marked amended', () async {
      final repo = paymentsFor(db, ownerAccess);
      final a = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      final b = await repo.record(tenantId: tenantId, amount: 2000000, method: PaymentMethod.cash);
      final c = await repo.record(tenantId: tenantId, amount: 500000, method: PaymentMethod.cash);
      expect((await repo.balanceAfter(a.paymentId)).outstanding, 2000000);
      expect((await repo.balanceAfter(b.paymentId)).outstanding, 0);
      final last = await repo.balanceAfter(c.paymentId);
      expect(last.outstanding, 0);
      expect(last.advance, 500000);
      expect(await repo.wasAmended(a.paymentId), isFalse);
      await repo.editPayment(a.paymentId, amount: 900000, confirmation: await confirmed(SensitiveAction.paymentEdit, a.paymentId));
      expect(await repo.wasAmended(a.paymentId), isTrue);
    });
  });
}
