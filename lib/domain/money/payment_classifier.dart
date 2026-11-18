import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/domain/money/ledger.dart';

/// How a payment is labelled given what was owed when it was made.
class PaymentClassification {
  /// Creates a classification.
  const PaymentClassification({required this.type, required this.status, required this.forMonth});

  /// rent, partial or advance for rent payments; the given type otherwise.
  final PaymentType type;

  /// paid, partial or advance.
  final PaymentStatus status;

  /// The oldest month this payment went towards (or the next month for advance money).
  final String forMonth;
}

/// Decides type, status and month of a payment of [amount].
///
/// [charges] are what was owed at that moment and [priorPayments] what was already paid
/// (only payments that count against dues). A payment that does not count (a deposit) is
/// always "paid" for [currentMonth]. This one function is used both when a payment is recorded
/// and when labels are recalculated after a correction, so they can never disagree.
PaymentClassification classifyPayment({
  required List<MonthCharge> charges,
  required Iterable<int> priorPayments,
  required int amount,
  required PaymentType type,
  required bool countsAgainstDues,
  required String currentMonth,
}) {
  if (!countsAgainstDues) {
    return PaymentClassification(type: type, status: PaymentStatus.paid, forMonth: currentMonth);
  }
  final before = buildLedger(charges: charges, payments: priorPayments);
  final owed = before.outstanding;
  final left = owed - amount;
  final status = left > 0
      ? PaymentStatus.partial
      : left == 0
          ? PaymentStatus.paid
          : PaymentStatus.advance;
  var effective = type;
  if (type == PaymentType.rent) {
    effective = owed == 0
        ? PaymentType.advance
        : amount < owed
            ? PaymentType.partial
            : PaymentType.rent;
  }
  final open = before.months.where((m) => m.remaining > 0);
  final forMonth = open.isNotEmpty ? open.first.month : nextMonthKey(currentMonth);
  return PaymentClassification(type: effective, status: status, forMonth: forMonth);
}
