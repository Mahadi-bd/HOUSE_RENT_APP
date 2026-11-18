/// Rent charged for one month, in poisha (1 BDT = 100 poisha).
class MonthCharge {
  /// Creates a charge. [month] is `yyyy-MM`.
  const MonthCharge(this.month, this.amount);

  /// Month key like `2026-11`.
  final String month;

  /// Amount in poisha. Never negative.
  final int amount;
}

/// What one month looks like after payments are applied.
class MonthBalance {
  /// Creates a balance.
  const MonthBalance({required this.month, required this.charged, required this.paid});

  /// Month key.
  final String month;

  /// Charged amount.
  final int charged;

  /// Amount of payments applied to this month.
  final int paid;

  /// Still to pay for this month.
  int get remaining => charged - paid;
}

/// The result of applying payments to charges.
class LedgerSummary {
  /// Creates a summary.
  const LedgerSummary({
    required this.months,
    required this.totalCharged,
    required this.totalApplied,
    required this.advanceCredit,
  });

  /// Month by month, oldest first.
  final List<MonthBalance> months;

  /// Sum of all charges.
  final int totalCharged;

  /// Payments that went against charges.
  final int totalApplied;

  /// Money paid beyond all charges (advance), in poisha.
  final int advanceCredit;

  /// Amount still owed across all months.
  int get outstanding => totalCharged - totalApplied;
}

/// Applies [payments] to [charges], oldest month first. All amounts are integer poisha, so
/// there is no rounding error. Throws [ArgumentError] on a negative amount.
LedgerSummary buildLedger({
  required List<MonthCharge> charges,
  required Iterable<int> payments,
}) {
  for (final charge in charges) {
    if (charge.amount < 0) {
      throw ArgumentError.value(charge.amount, 'charge', 'must not be negative');
    }
  }
  var pool = 0;
  for (final payment in payments) {
    if (payment < 0) {
      throw ArgumentError.value(payment, 'payment', 'must not be negative');
    }
    pool += payment;
  }
  final sorted = [...charges]..sort((a, b) => a.month.compareTo(b.month));
  final months = <MonthBalance>[];
  var charged = 0;
  var applied = 0;
  for (final charge in sorted) {
    final paid = pool < charge.amount ? pool : charge.amount;
    pool -= paid;
    charged += charge.amount;
    applied += paid;
    months.add(MonthBalance(month: charge.month, charged: charge.amount, paid: paid));
  }
  return LedgerSummary(
    months: months,
    totalCharged: charged,
    totalApplied: applied,
    advanceCredit: pool,
  );
}
