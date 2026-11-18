import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/domain/money/ledger.dart';

/// One charge of [monthlyDue] for every month from the lease start through [now]
/// (or the lease end if that is earlier). The first month is charged in full (no proration).
List<MonthCharge> rentCharges({
  required DateTime leaseStart,
  required int monthlyDue,
  required DateTime now,
  DateTime? leaseEnd,
}) {
  final first = monthKeyOf(leaseStart);
  var last = monthKeyOf(now);
  if (leaseEnd != null) {
    final end = monthKeyOf(leaseEnd);
    if (end.compareTo(last) < 0) {
      last = end;
    }
  }
  return [for (final month in monthsThrough(first, last)) MonthCharge(month, monthlyDue)];
}

/// Adds optional extra charges (electricity, gas, fines...) to the rent charges, month by month.
/// A month that only has extras (for example a fine after the lease ended) still appears.
List<MonthCharge> mergeExtraCharges(
  List<MonthCharge> base,
  Iterable<({String month, int amount})> extras,
) {
  final totals = <String, int>{for (final c in base) c.month: c.amount};
  for (final e in extras) {
    if (e.amount < 0) {
      throw ArgumentError.value(e.amount, 'extra charge', 'must not be negative');
    }
    totals[e.month] = (totals[e.month] ?? 0) + e.amount;
  }
  final months = totals.keys.toList()..sort();
  return [for (final m in months) MonthCharge(m, totals[m]!)];
}
