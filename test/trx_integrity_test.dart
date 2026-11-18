import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
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

  Future<PaymentRow> pay(PaymentMethod m, String? trx, {int amount = 1000}) async {
    final r = await paymentsFor(db, ownerAccess).record(tenantId: tenantId, amount: amount, method: m, trxId: trx);
    return PaymentRow(r.paymentId);
  }

  test('the same TrxID for the same provider is refused (also with other letter case)', () async {
    await pay(PaymentMethod.bkash, 'AB12CD');
    await expectLater(pay(PaymentMethod.bkash, 'AB12CD'), throwsStateError);
    await expectLater(pay(PaymentMethod.bkash, ' ab12cd '), throwsStateError);
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('the same TrxID at a different provider is allowed (scope: organization + provider)', () async {
    await pay(PaymentMethod.bkash, 'AB12CD');
    await pay(PaymentMethod.nagad, 'AB12CD');
    expect(await db.select(db.payments).get(), hasLength(2));
  });

  test('editing a payment to a TrxID that already exists is refused', () async {
    final a = await pay(PaymentMethod.bkash, 'AAA111');
    final b = await pay(PaymentMethod.bkash, 'BBB222');
    final repo = paymentsFor(db, ownerAccess);
    await expectLater(
      repo.editPayment(b.id, trxId: 'aaa111', confirmation: await confirmed(SensitiveAction.paymentEdit, b.id)),
      throwsStateError,
    );
    // Keeping its own TrxID is fine.
    await repo.editPayment(b.id, trxId: 'BBB222', amount: 2000, confirmation: await confirmed(SensitiveAction.paymentEdit, b.id));
    expect(a.id, isNot(b.id));
  });

  test('a mobile-money payment cannot lose its TrxID by editing', () async {
    final a = await pay(PaymentMethod.bkash, 'AAA111');
    await expectLater(
      paymentsFor(db, ownerAccess)
          .editPayment(a.id, trxId: '  ', confirmation: await confirmed(SensitiveAction.paymentEdit, a.id)),
      throwsArgumentError,
    );
  });

  test('the database itself refuses a duplicate even if the repository is bypassed', () async {
    await pay(PaymentMethod.rocket, 'ROCK1');
    final existing = await db.select(db.payments).getSingle();
    await expectLater(
      db.into(db.payments).insert(
            PaymentsCompanion.insert(
              id: 'raw',
              orgId: existing.orgId,
              createdAt: existing.createdAt,
              updatedAt: existing.updatedAt,
              createdBy: 'u',
              deviceId: 'd',
              hlc: '1',
              tenantId: existing.tenantId,
              unitId: existing.unitId,
              amount: 5,
              method: PaymentMethod.rocket,
              type: PaymentType.rent,
              forMonth: '2026-11',
              paidAt: existing.paidAt,
              receiptNo: 'RAW-1',
              recordedBy: 'u',
              status: PaymentStatus.paid,
              trxId: const Value('ROCK1'),
            ),
          ),
      throwsA(anything),
    );
  });

  test('two payments written at the same time with one TrxID: exactly one is saved', () async {
    final repo = paymentsFor(db, ownerAccess);
    final results = await Future.wait<Object?>([
      repo.record(tenantId: tenantId, amount: 500, method: PaymentMethod.nagad, trxId: 'RACE1').then<Object?>((v) => v).catchError((Object e) => e),
      repo.record(tenantId: tenantId, amount: 500, method: PaymentMethod.nagad, trxId: 'RACE1').then<Object?>((v) => v).catchError((Object e) => e),
    ]);
    expect(results.whereType<Error>().length + results.whereType<Exception>().length, 1);
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('a cancelled payment frees its TrxID', () async {
    final a = await pay(PaymentMethod.bkash, 'FREE1');
    await paymentsFor(db, ownerAccess)
        .voidPayment(a.id, reason: 'typo', confirmation: await confirmed(SensitiveAction.paymentVoid, a.id));
    await pay(PaymentMethod.bkash, 'FREE1');
    expect(await db.select(db.payments).get(), hasLength(2));
  });

  test('restore/import: existingTrxIds lists the conflicts to resolve first', () async {
    await pay(PaymentMethod.bkash, 'AAA111');
    await pay(PaymentMethod.bkash, 'BBB222');
    final conflicts = await paymentsFor(db, ownerAccess)
        .existingTrxIds(PaymentMethod.bkash, ['aaa111', 'ZZZ999', 'BBB222']);
    expect(conflicts, {'AAA111', 'BBB222'});
    expect(await paymentsFor(db, ownerAccess).existingTrxIds(PaymentMethod.nagad, ['AAA111']), isEmpty);
  });
}

class PaymentRow {
  const PaymentRow(this.id);
  final String id;
}
