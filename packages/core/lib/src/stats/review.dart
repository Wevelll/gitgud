import '../calendar/calendar_provider.dart';
import '../models/day_profile.dart';
import '../models/habit.dart';
import '../models/recurring_task.dart';
import '../models/time_log.dart';
import '../time/civil_date.dart';
import 'plan_vs_actual.dart';
import 'streaks.dart';

/// The review window (SPEC §12.7). Ranges end at the reference day and look back
/// [spanDays] further, matching the day/week/month convention used by
/// `get_stats`.
enum ReviewRange {
  day(0),
  week(6),
  month(29),
  year(364);

  const ReviewRange(this.spanDays);
  final int spanDays;

  /// Inclusive list of dates for this range ending at [asOf].
  List<CivilDate> datesEndingAt(CivilDate asOf) =>
      asOf.addDays(-spanDays).rangeTo(asOf);
}

/// A streak paired with the label it belongs to, for the review UI.
class NamedStreak {
  const NamedStreak(
      {required this.id, required this.label, required this.streak});
  final String id;
  final String label;
  final StreakInfo streak;
}

/// A full periodic review (SPEC §12.7): plan-vs-actual variance, task/habit
/// streaks, task completion counts, and calendar load — all read-only
/// aggregation over existing primitives. No new mutable state.
class PeriodicReview {
  const PeriodicReview({
    required this.range,
    required this.from,
    required this.to,
    required this.variance,
    required this.taskStreaks,
    required this.habitStreaks,
    required this.dueTaskInstances,
    required this.completedTaskInstances,
    required this.calendarMinutes,
  });

  final ReviewRange range;
  final CivilDate from;
  final CivilDate to;
  final List<CategoryVariance> variance;
  final List<NamedStreak> taskStreaks;
  final List<NamedStreak> habitStreaks;

  /// Total (task, date) slots the tray demanded over the range…
  final int dueTaskInstances;

  /// …and how many were checked off. Ratio = completion rate.
  final int completedTaskInstances;

  /// Booked calendar minutes drawn on the ring over the range (clipped per day,
  /// so multi-day events aren't double-counted). Zero when no calendar is wired.
  final int calendarMinutes;

  double get taskCompletionRate =>
      dueTaskInstances == 0 ? 0 : completedTaskInstances / dueTaskInstances;
}

/// Builds a [PeriodicReview] for [range] ending at [asOf]. [calendar] is
/// optional; when absent, [PeriodicReview.calendarMinutes] is 0. Streaks are
/// computed as of [asOf] regardless of range (a streak is inherently a
/// look-back), so the review's "current streak" matches the dial's.
PeriodicReview buildReview({
  required ReviewRange range,
  required CivilDate asOf,
  required DayProfile Function(CivilDate date) profileForDate,
  required Iterable<TimeLog> logs,
  required List<RecurringTask> tasks,
  required Iterable<TaskCompletion> completions,
  required List<Habit> habits,
  required Iterable<HabitEvent> habitEvents,
  CalendarProvider? calendar,
}) {
  final dates = range.datesEndingAt(asOf);
  final from = dates.first;
  final to = dates.last;

  final variance = planVsActual(
    dates: dates,
    profileForDate: profileForDate,
    logs: logs,
  );

  final completionsList = completions.toList();
  var due = 0;
  var done = 0;
  final doneKeys = <String>{
    for (final c in completionsList) '${c.taskId}@${c.date.iso}',
  };
  for (final date in dates) {
    for (final t in tasks) {
      if (t.isDueOn(date)) {
        due++;
        if (doneKeys.contains('${t.id}@${date.iso}')) done++;
      }
    }
  }

  final taskStreaks = [
    for (final t in tasks)
      if (!t.archived)
        NamedStreak(
          id: t.id,
          label: t.label,
          streak: taskStreak(t, completionsList, asOf: asOf),
        ),
  ];
  final eventsList = habitEvents.toList();
  final habitStreaks = [
    for (final h in habits)
      if (!h.archived)
        NamedStreak(
          id: h.id,
          label: h.label,
          streak: habitStreak(h, eventsList, asOf: asOf),
        ),
  ];

  var calendarMinutes = 0;
  if (calendar != null) {
    for (final date in dates) {
      for (final e in calendar.overlayOn(date).timed) {
        calendarMinutes += e.durationMin;
      }
    }
  }

  return PeriodicReview(
    range: range,
    from: from,
    to: to,
    variance: variance,
    taskStreaks: taskStreaks,
    habitStreaks: habitStreaks,
    dueTaskInstances: due,
    completedTaskInstances: done,
    calendarMinutes: calendarMinutes,
  );
}
