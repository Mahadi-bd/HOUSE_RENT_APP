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
  late String tenantId;
  late String propertyId;

  setUp(() async {
    db = memoryDb();
    final ids = await seedTenant(db); // rent 10,000 BDT, lease from Sep, "now" is Nov 10
    tenantId = ids.tenantId;
    propertyId = ids.propertyId;
  });
  tearDown(() => db.close());

  final owner = ownerAccess;

  test('rent owed since the lease start is three months (Sep, Oct, Nov)', () async {
    final ledger = await paymentsFor(db, owner).ledgerFor(tenantId);
    expect(ledger.outstanding, 3000000);
  });

  group('partial and advance logic', () {
    test('partial, then full, then advance', () async {
      final repo = paymentsFor(db, owner);

      final first = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      expect(first.outstandingAfter, 2000000);
      expect(first.advanceCredit, 0);

      final second = await repo.record(tenantId: tenantId, amount: 2000000, method: PaymentMethod.cash);
      expect(second.outstandingAfter, 0);

      final third = await repo.record(tenantId: tenantId, amount: 500000, method: PaymentMethod.cash);
      expect(third.outstandingAfter, 0);
      expect(third.advanceCredit, 500000);

      final rows = await repo.listForTenant(tenantId);
      final byReceipt = {for (final p in rows) p.receiptNo: p};
      expect(byReceipt[first.receiptNo]!.type, PaymentType.partial);
      expect(byReceipt[first.receiptNo]!.status, PaymentStatus.partial);
      expect(byReceipt[first.receiptNo]!.forMonth, '2026-09');
      expect(byReceipt[second.receiptNo]!.type, PaymentType.rent);
      expect(byReceipt[second.receiptNo]!.status, PaymentStatus.paid);
      expect(byReceipt[third.receiptNo]!.type, PaymentType.advance);
      expect(byReceipt[third.receiptNo]!.status, PaymentStatus.advance);
      expect(byReceipt[third.receiptNo]!.forMonth, '2026-12');
    });

    test('paying more than the debt records the surplus as advance credit', () async {
      final r = await paymentsFor(db, owner)
          .record(tenantId: tenantId, amount: 3100050, method: PaymentMethod.cash);
      expect(r.outstandingAfter, 0);
      expect(r.advanceCredit, 100050);
    });

    test('deposits do not reduce rent owed', () async {
      final repo = paymentsFor(db, owner);
      await repo.record(
        tenantId: tenantId,
        amount: 5000000,
        method: PaymentMethod.cash,
        type: PaymentType.deposit,
      );
      expect((await repo.ledgerFor(tenantId)).outstanding, 3000000);
    });
  });

  group('receipts', () {
    test('numbers are unique, ordered and well formed', () async {
      final repo = paymentsFor(db, owner);
      final a = await repo.record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      final b = await repo.record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      expect(a.receiptNo, matches(RegExp(r'^R2611-[0-9A-F]{4}-0001$')));
      expect(b.receiptNo, endsWith('-0002'));
    });

    test('a number is never reused, even after a payment is voided', () async {
      final repo = paymentsFor(db, owner);
      final a = await repo.record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      await repo.voidPayment(
        a.paymentId,
        reason: 'typo',
        confirmation: await confirmed(SensitiveAction.paymentVoid, a.paymentId),
      );
      final b = await repo.record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      expect(b.receiptNo, isNot(a.receiptNo));
    });
  });

  group('input checks', () {
    test('zero, negative and absurd amounts are rejected', () async {
      final repo = paymentsFor(db, owner);
      for (final bad in [0, -5, 100000000001]) {
        await expectLater(
          repo.record(tenantId: tenantId, amount: bad, method: PaymentMethod.cash),
          throwsArgumentError,
        );
      }
      expect(await db.select(db.payments).get(), isEmpty);
    });

    test('mobile money needs a transaction id, and it cannot be used twice', () async {
      final repo = paymentsFor(db, owner);
      await expectLater(
        repo.record(tenantId: tenantId, amount: 1000, method: PaymentMethod.bkash),
        throwsArgumentError,
      );
      await repo.record(tenantId: tenantId, amount: 1000, method: PaymentMethod.bkash, trxId: 'AB12CD');
      await expectLater(
        repo.record(tenantId: tenantId, amount: 1000, method: PaymentMethod.nagad, trxId: 'AB12CD'),
        throwsStateError,
      );
      expect(await db.select(db.payments).get(), hasLength(1));
    });

    test('an unknown tenant is refused', () async {
      await expectLater(
        paymentsFor(db, owner).record(tenantId: 'nope', amount: 100, method: PaymentMethod.cash),
        throwsStateError,
      );
    });
  });

  group('who can do what', () {
    test('caretaker and manager can record; tenant and nobody cannot', () async {
      for (final role in [Role.caretaker, Role.manager]) {
        await paymentsFor(db, MemberAccess(role: role))
            .record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      }
      for (final access in [const MemberAccess(role: Role.tenant), null]) {
        await expectLater(
          paymentsFor(db, access).record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash),
          throwsA(isA<PermissionDenied>()),
        );
      }
    });

    test('a manager scoped to another property cannot record', () async {
      final scoped = MemberAccess(role: Role.manager, propertyScope: {'another-property'});
      await expectLater(
        paymentsFor(db, scoped).record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash),
        throwsA(isA<PermissionDenied>()),
      );
      final inScope = MemberAccess(role: Role.manager, propertyScope: {propertyId});
      await paymentsFor(db, inScope)
          .record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
    });

    test('only owner/admin can edit or void, and only with a confirmation for that payment', () async {
      final r = await paymentsFor(db, owner)
          .record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
        final repo = paymentsFor(db, MemberAccess(role: role));
        await expectLater(
          repo.editPayment(
            r.paymentId,
            amount: 5,
            confirmation: await confirmed(SensitiveAction.paymentEdit, r.paymentId),
          ),
          throwsA(isA<PermissionDenied>()),
        );
        await expectLater(
          repo.voidPayment(
            r.paymentId,
            reason: 'x',
            confirmation: await confirmed(SensitiveAction.paymentVoid, r.paymentId),
          ),
          throwsA(isA<PermissionDenied>()),
        );
      }
      final repo = paymentsFor(db, owner);
      // Token for another record / another action is refused.
      await expectLater(
        repo.editPayment(
          r.paymentId,
          amount: 5,
          confirmation: await confirmed(SensitiveAction.paymentEdit, 'other-payment'),
        ),
        throwsA(isA<ConfirmationException>()),
      );
      await expectLater(
        repo.voidPayment(
          r.paymentId,
          reason: 'x',
          confirmation: await confirmed(SensitiveAction.paymentEdit, r.paymentId),
        ),
        throwsA(isA<ConfirmationException>()),
      );
      // A token works once only.
      final token = await confirmed(SensitiveAction.paymentEdit, r.paymentId);
      await repo.editPayment(r.paymentId, amount: 999999, confirmation: token);
      await expectLater(
        repo.editPayment(r.paymentId, amount: 888888, confirmation: token),
        throwsA(isA<ConfirmationException>()),
      );
    });

    test('a tenant sees only their own payments and ledger', () async {
      await paymentsFor(db, owner).record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash);
      final own = MemberAccess(role: Role.tenant, linkedTenantId: tenantId);
      final other = MemberAccess(role: Role.tenant, linkedTenantId: 'someone-else');
      expect(await paymentsFor(db, own).listForTenant(tenantId), hasLength(1));
      expect((await paymentsFor(db, own).ledgerFor(tenantId)).outstanding, 3000000 - 100);
      await expectLater(
        paymentsFor(db, other).listForTenant(tenantId),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('edit and void change the balance and are audited', () {
    test('void puts the money back on the ledger; edit changes it', () async {
      final repo = paymentsFor(db, owner);
      final a = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      final b = await repo.record(tenantId: tenantId, amount: 2000000, method: PaymentMethod.cash);
      expect((await repo.ledgerFor(tenantId)).outstanding, 0);

      await repo.voidPayment(
        b.paymentId,
        reason: 'entered twice',
        confirmation: await confirmed(SensitiveAction.paymentVoid, b.paymentId),
      );
      expect((await repo.ledgerFor(tenantId)).outstanding, 2000000);
      expect(await repo.listForTenant(tenantId), hasLength(1));

      await repo.editPayment(
        a.paymentId,
        amount: 1500000,
        confirmation: await confirmed(SensitiveAction.paymentEdit, a.paymentId),
      );
      expect((await repo.ledgerFor(tenantId)).outstanding, 1500000);

      await expectLater(
        repo.voidPayment(
          b.paymentId,
          reason: 'again',
          confirmation: await confirmed(SensitiveAction.paymentVoid, b.paymentId),
        ),
        throwsStateError,
      );
    });

    test('every change is in a valid audit chain with old and new values', () async {
      final repo = paymentsFor(db, owner);
      final a = await repo.record(tenantId: tenantId, amount: 1000000, method: PaymentMethod.cash);
      await repo.editPayment(
        a.paymentId,
        amount: 900000,
        confirmation: await confirmed(SensitiveAction.paymentEdit, a.paymentId),
      );
      await repo.voidPayment(
        a.paymentId,
        reason: 'refund',
        confirmation: await confirmed(SensitiveAction.paymentVoid, a.paymentId),
      );

      final logs = await db.select(db.auditLogs).get();
      final edit = logs.firstWhere((l) => l.action == 'payment.edit');
      expect(edit.oldValue, contains('1000000'));
      expect(edit.newValue, contains('900000'));
      expect(logs.map((l) => l.action), containsAll(['payment.record', 'payment.edit', 'payment.void']));
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('a failed write leaves no payment and no audit record behind', () async {
      final before = (await db.select(db.auditLogs).get()).length;
      await expectLater(
        paymentsFor(db, MemberAccess(role: Role.manager, propertyScope: {'x'}))
            .record(tenantId: tenantId, amount: 100, method: PaymentMethod.cash),
        throwsA(isA<PermissionDenied>()),
      );
      expect(await db.select(db.payments).get(), isEmpty);
      expect((await db.select(db.auditLogs).get()).length, before);
    });
  });
}
