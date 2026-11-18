/// Bangladesh time is UTC+6 all year (no daylight saving).
const bangladeshOffset = Duration(hours: 6);

/// The Bangladesh calendar month of [instant], as `yyyy-MM`.
String monthKeyOf(DateTime instant) {
  final local = instant.toUtc().add(bangladeshOffset);
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';
}

/// The month after [monthKey] (`yyyy-MM`).
String nextMonthKey(String monthKey) {
  final year = int.parse(monthKey.substring(0, 4));
  final month = int.parse(monthKey.substring(5, 7));
  final next = month == 12 ? DateTime.utc(year + 1) : DateTime.utc(year, month + 1);
  return '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}';
}

/// Every month from [start] to [end], both included. Empty when [start] is after [end].
List<String> monthsThrough(String start, String end) {
  final months = <String>[];
  var current = start;
  while (current.compareTo(end) <= 0) {
    months.add(current);
    current = nextMonthKey(current);
  }
  return months;
}
