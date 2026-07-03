import '../time/civil_date.dart';

/// A recurrence rule for an untimed task (SPEC §3): daily, weekly on given
/// weekdays, every-N-days from an anchor, or a fixed set of dates.
///
/// Rules serialize to a compact string ([encode]) for the `recurrence_rule`
/// column and round-trip via [Recurrence.parse], so persistence needs no
/// separate schema. Evaluation is [isDueOn]; completion is tracked per date
/// elsewhere.
sealed class Recurrence {
  const Recurrence();

  /// Whether a task with this rule should appear in the tray on [date].
  bool isDueOn(CivilDate date);

  /// Compact persistable form. Round-trips through [Recurrence.parse].
  String encode();

  factory Recurrence.parse(String rule) {
    final s = rule.trim();
    if (s == 'daily') return const DailyRecurrence();

    final colon = s.indexOf(':');
    if (colon == -1) {
      throw FormatException('Unknown recurrence rule', rule);
    }
    final kind = s.substring(0, colon);
    final body = s.substring(colon + 1);
    switch (kind) {
      case 'weekly':
        final days = body
            .split(',')
            .where((p) => p.isNotEmpty)
            .map((p) => int.parse(p))
            .toSet();
        return WeeklyRecurrence(days);
      case 'interval':
        final at = body.indexOf('@');
        if (at == -1) throw FormatException('interval needs @anchor', rule);
        final n = int.parse(body.substring(0, at));
        final anchor = CivilDate.parse(body.substring(at + 1));
        return IntervalRecurrence(n, anchor);
      case 'dates':
        final dates = body
            .split(',')
            .where((p) => p.isNotEmpty)
            .map(CivilDate.parse)
            .toSet();
        return DatesRecurrence(dates);
      default:
        throw FormatException('Unknown recurrence kind "$kind"', rule);
    }
  }
}

/// Due every day.
class DailyRecurrence extends Recurrence {
  const DailyRecurrence();

  @override
  bool isDueOn(CivilDate date) => true;

  @override
  String encode() => 'daily';

  @override
  bool operator ==(Object other) => other is DailyRecurrence;
  @override
  int get hashCode => (DailyRecurrence).hashCode;
}

/// Due on specific ISO weekdays (Monday = 1 … Sunday = 7).
class WeeklyRecurrence extends Recurrence {
  WeeklyRecurrence(Set<int> weekdays)
      : weekdays = Set.unmodifiable(weekdays.toList()..sort()) {
    if (weekdays.isEmpty) {
      throw ArgumentError('WeeklyRecurrence needs at least one weekday');
    }
    if (weekdays.any((d) => d < 1 || d > 7)) {
      throw ArgumentError('Weekdays must be in 1..7 (Mon..Sun)');
    }
  }

  final Set<int> weekdays;

  @override
  bool isDueOn(CivilDate date) => weekdays.contains(date.weekday);

  @override
  String encode() => 'weekly:${weekdays.join(',')}';

  @override
  bool operator ==(Object other) =>
      other is WeeklyRecurrence &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);
  @override
  int get hashCode => Object.hashAllUnordered(weekdays);
}

/// Due every [intervalDays] days counting from [anchor] (inclusive), never
/// before the anchor.
class IntervalRecurrence extends Recurrence {
  IntervalRecurrence(this.intervalDays, this.anchor) {
    if (intervalDays < 1) {
      throw ArgumentError('intervalDays must be >= 1');
    }
  }

  final int intervalDays;
  final CivilDate anchor;

  @override
  bool isDueOn(CivilDate date) {
    final diff = anchor.daysUntil(date);
    if (diff < 0) return false;
    return diff % intervalDays == 0;
  }

  @override
  String encode() => 'interval:$intervalDays@${anchor.iso}';

  @override
  bool operator ==(Object other) =>
      other is IntervalRecurrence &&
      other.intervalDays == intervalDays &&
      other.anchor == anchor;
  @override
  int get hashCode => Object.hash(intervalDays, anchor);
}

/// Due only on an explicit set of dates.
class DatesRecurrence extends Recurrence {
  DatesRecurrence(Set<CivilDate> dates) : dates = Set.unmodifiable(dates) {
    if (dates.isEmpty) {
      throw ArgumentError('DatesRecurrence needs at least one date');
    }
  }

  final Set<CivilDate> dates;

  @override
  bool isDueOn(CivilDate date) => dates.contains(date);

  @override
  String encode() {
    final sorted = dates.toList()..sort();
    return 'dates:${sorted.map((d) => d.iso).join(',')}';
  }

  @override
  bool operator ==(Object other) =>
      other is DatesRecurrence &&
      other.dates.length == dates.length &&
      other.dates.containsAll(dates);
  @override
  int get hashCode => Object.hashAllUnordered(dates);
}
