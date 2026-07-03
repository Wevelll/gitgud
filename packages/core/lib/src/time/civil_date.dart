/// A calendar date with no time and no timezone — `YYYY-MM-DD` (SPEC §5).
///
/// `core` is platform-agnostic, so this uses only `dart:core`'s [DateTime]
/// (available on web) and never touches wall-clock time zones: all arithmetic
/// goes through UTC to stay DST-proof. This is the type recurrence rules and
/// completions are keyed on — distinct from a timestamp (an ISO-8601 instant).
library;

class CivilDate implements Comparable<CivilDate> {
  const CivilDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// Parses `YYYY-MM-DD`. Throws [FormatException] on anything else, including
  /// impossible dates like `2026-02-30`.
  factory CivilDate.parse(String input) {
    final s = input.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) throw FormatException('Expected YYYY-MM-DD', input);
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) {
      throw FormatException('Month/day out of range', input);
    }
    // Round-trip through DateTime to reject non-existent dates (e.g. Feb 30).
    final dt = DateTime.utc(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) {
      throw FormatException('Not a real calendar date', input);
    }
    return CivilDate(y, mo, d);
  }

  /// The civil date of [dt] in its own local frame (date part only).
  factory CivilDate.fromDateTime(DateTime dt) =>
      CivilDate(dt.year, dt.month, dt.day);

  DateTime get _utc => DateTime.utc(year, month, day);

  /// ISO-8601 weekday: Monday = 1 … Sunday = 7.
  int get weekday => _utc.weekday;

  /// This date shifted by [days] (may be negative).
  CivilDate addDays(int days) =>
      CivilDate.fromDateTime(_utc.add(Duration(days: days)));

  /// Whole days from this date to [other] (positive if [other] is later).
  int daysUntil(CivilDate other) => other._utc.difference(_utc).inDays;

  /// Inclusive list of dates from this date to [end]. Empty if [end] precedes.
  List<CivilDate> rangeTo(CivilDate end) {
    final n = daysUntil(end);
    if (n < 0) return const [];
    return List.generate(n + 1, (i) => addDays(i));
  }

  String get iso => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CivilDate other) =>
      daysUntil(other) == 0 ? 0 : (_utc.isBefore(other._utc) ? -1 : 1);

  bool isBefore(CivilDate other) => compareTo(other) < 0;
  bool isAfter(CivilDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}
