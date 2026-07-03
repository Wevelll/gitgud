import '../models/day_profile.dart';
import '../models/time_log.dart';
import '../time/civil_date.dart';

/// Planned-vs-actual for one category (SPEC §4). [deltaMin] is actual − planned:
/// negative means you spent less than planned, positive means more.
class CategoryVariance {
  const CategoryVariance({
    required this.category,
    required this.plannedMin,
    required this.actualMin,
  });

  final String category;
  final int plannedMin;
  final int actualMin;

  int get deltaMin => actualMin - plannedMin;

  @override
  bool operator ==(Object other) =>
      other is CategoryVariance &&
      other.category == category &&
      other.plannedMin == plannedMin &&
      other.actualMin == actualMin;

  @override
  int get hashCode => Object.hash(category, plannedMin, actualMin);

  @override
  String toString() =>
      'CategoryVariance($category: planned $plannedMin, actual $actualMin, '
      'Δ$deltaMin)';
}

/// Minutes planned per category for a single day, keyed by segment name.
/// Segments sharing a name (e.g. two "Work" blocks) accumulate.
Map<String, int> plannedByCategory(DayProfile profile) {
  final out = <String, int>{};
  for (final seg in profile.segments) {
    out[seg.name] = (out[seg.name] ?? 0) + seg.durationMin;
  }
  return out;
}

/// Minutes actually logged per category across [logs].
Map<String, int> actualByCategory(Iterable<TimeLog> logs) {
  final out = <String, int>{};
  for (final log in logs) {
    out[log.category] = (out[log.category] ?? 0) + log.durationMin;
  }
  return out;
}

/// Joins planned and actual maps into a per-category variance list over the
/// union of categories, sorted by category name for stable output.
List<CategoryVariance> mergeVariance(
  Map<String, int> planned,
  Map<String, int> actual,
) {
  final categories = <String>{...planned.keys, ...actual.keys}.toList()..sort();
  return [
    for (final c in categories)
      CategoryVariance(
        category: c,
        plannedMin: planned[c] ?? 0,
        actualMin: actual[c] ?? 0,
      ),
  ];
}

/// Full plan-vs-actual over a date range (SPEC §4, MCP `get_stats`).
///
/// [profileForDate] returns the active [DayProfile] for a given day, so the
/// planned side scales correctly across a range even when weekdays use
/// different profiles. Actuals are taken from [logs] whose [TimeLog.date] falls
/// within [dates]. Returns per-category variance sorted by category.
List<CategoryVariance> planVsActual({
  required List<CivilDate> dates,
  required DayProfile Function(CivilDate date) profileForDate,
  required Iterable<TimeLog> logs,
}) {
  final planned = <String, int>{};
  for (final date in dates) {
    final dayPlan = plannedByCategory(profileForDate(date));
    dayPlan.forEach((cat, min) {
      planned[cat] = (planned[cat] ?? 0) + min;
    });
  }

  final dateSet = dates.toSet();
  final actual = actualByCategory(logs.where((l) => dateSet.contains(l.date)));

  return mergeVariance(planned, actual);
}
