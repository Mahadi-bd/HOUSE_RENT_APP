import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/domain/money/ledger.dart';
import 'package:rent_solution/domain/money/rent_charges.dart';

void main() {
  const charges = [
    MonthCharge('2026-09', 1000000),
    MonthCharge('2026-10', 1000000),
    MonthCharge('2026-11', 1000000),
  ];

  test('no payments: everything is outstanding', () {
    final l = buildLedger(charges: charges, payments: const []);
    expect(l.outstanding, 3000000);
    expect(l.advanceCredit, 0);
    expect(l.months.map((m) => m.remaining), [1000000, 1000000, 1000000]);
  });

  test('payments clear the oldest month first', () {
    final l = buildLedger(charges: charges, payments: const [1000000, 500000]);
    expect(l.months.map((m) => m.paid), [1000000, 500000, 0]);
    expect(l.outstanding, 1500000);
    expect(l.advanceCredit, 0);
  });

  test('paying exactly everything leaves nothing owed and no advance', () {
    final l = buildLedger(charges: charges, payments: const [3000000]);
    expect(l.outstanding, 0);
    expect(l.advanceCredit, 0);
  });

  test('paying more than everything becomes advance credit', () {
    final l = buildLedger(charges: charges, payments: const [3000000, 250050]);
    expect(l.outstanding, 0);
    expect(l.advanceCredit, 250050);
  });

  test('order of payments and charges does not change the result', () {
    final a = buildLedger(charges: charges, payments: const [700000, 1300000]);
    final b = buildLedger(charges: charges.reversed.toList(), payments: const [1300000, 700000]);
    expect(a.outstanding, b.outstanding);
    expect(a.months.map((m) => m.paid), b.months.map((m) => m.paid));
  });

  test('money is exact: many small payments add up to the poisha', () {
    final l = buildLedger(
      charges: const [MonthCharge('2026-09', 1000000)],
      payments: List.filled(100, 10000),
    );
    expect(l.outstanding, 0);
    expect(l.advanceCredit, 0);
  });

  test('negative amounts are rejected', () {
    expect(() => buildLedger(charges: charges, payments: const [-1]), throwsArgumentError);
    expect(
      () => buildLedger(charges: const [MonthCharge('2026-09', -5)], payments: const []),
      throwsArgumentError,
    );
  });

  group('rentCharges', () {
    test('one charge per month from lease start through now, in Bangladesh time', () {
      final result = rentCharges(
        leaseStart: DateTime.utc(2026, 9, 1),
        monthlyDue: 1200000,
        now: DateTime.utc(2026, 11, 10),
      );
      expect(result.map((c) => c.month), ['2026-09', '2026-10', '2026-11']);
      expect(result.every((c) => c.amount == 1200000), isTrue);
    });

    test('stops at the lease end', () {
      final result = rentCharges(
        leaseStart: DateTime.utc(2026, 1, 1),
        leaseEnd: DateTime.utc(2026, 3, 15),
        monthlyDue: 1,
        now: DateTime.utc(2026, 11, 10),
      );
      expect(result.map((c) => c.month), ['2026-01', '2026-02', '2026-03']);
    });

    test('a lease that has not started yet has no charges', () {
      final result = rentCharges(
        leaseStart: DateTime.utc(2027, 1, 1),
        monthlyDue: 1,
        now: DateTime.utc(2026, 11, 10),
      );
      expect(result, isEmpty);
    });
  });
}
