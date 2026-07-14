import '../models/habit.dart';
import '../models/recurring_task.dart';
import '../time/civil_date.dart';

/// A current + longest streak, in days (SPEC §12.5).
class StreakInfo {
  const StreakInfo({required this.current, required this.longest});

  /// Consecutive successful days ending at (or just before) the reference day.
  final int current;

  /// The longest run of successful days seen in the scanned window.
  final int longest;

  @override
  bool operator ==(Object other) =>
      other is StreakInfo &&
      other.current == current &&
      other.longest == longest;

  @override
  int get hashCode => Object.hash(current, longest);

  @override
  String toString() => 'StreakInfo(current: $current, longest: $longest)';
}

/// Streak for a recurring task (SPEC §12.5), computed from its completion
/// history and its own recurrence rule.
///
/// Only days the task is **due** count toward or against the streak — a weekly
/// task doesn't break on its off-days (grace by design). The reference day
/// [asOf] gets a grace pass: if it's a due day that isn't done yet, the streak
/// isn't broken (you still have the day to do it) — but an earlier missed due
/// day does break it. [lookbackDays] bounds the scan.
StreakInfo taskStreak(
  RecurringTask task,
  Iterable<TaskCompletion> completions, {
  required CivilDate asOf,
  int lookbackDays = 366,
}) {
  final done = <CivilDate>{
    for (final c in completions)
      if (c.taskId == task.id) c.date,
  };
  return _streak(
    asOf: asOf,
    lookbackDays: lookbackDays,
    isCandidate: task.recurrence.isDueOn,
    succeeded: done.contains,
  );
}

/// Whether a habit's tally on a date counts as a successful day (SPEC §12.5):
/// a [HabitPolarity.good] habit reaches its target (or logs at least once when
/// it has no target); a [HabitPolarity.bad] habit stays at or under its cap (or
/// stays clean at zero when it has no cap).
bool habitDaySucceeded(Habit habit, int count) {
  final target = habit.dailyTarget;
  switch (habit.polarity) {
    case HabitPolarity.good:
      return target == null ? count > 0 : count >= target;
    case HabitPolarity.bad:
      return target == null ? count == 0 : count <= target;
  }
}

/// Streak for a countable habit (SPEC §12.5), computed from its event history.
///
/// Every day is a candidate (habits have no recurrence). Success is
/// [habitDaySucceeded]. [asOf] gets the same grace pass as tasks: a not-yet-met
/// [HabitPolarity.good] target on the reference day doesn't break the streak.
/// [lookbackDays] bounds the scan.
StreakInfo habitStreak(
  Habit habit,
  Iterable<HabitEvent> events, {
  required CivilDate asOf,
  int lookbackDays = 366,
}) {
  final counts = <CivilDate, int>{};
  for (final e in events) {
    if (e.habitId == habit.id) {
      counts[e.date] = (counts[e.date] ?? 0) + 1;
    }
  }
  return _streak(
    asOf: asOf,
    lookbackDays: lookbackDays,
    isCandidate: (_) => true,
    succeeded: (d) => habitDaySucceeded(habit, counts[d] ?? 0),
  );
}

/// Shared streak walk over candidate days. [isCandidate] filters which days
/// count (e.g. a task's due days); [succeeded] says whether a candidate day was
/// a success. The current streak walks back from [asOf] (with a grace pass on
/// [asOf] itself); the longest walks the whole window.
StreakInfo _streak({
  required CivilDate asOf,
  required int lookbackDays,
  required bool Function(CivilDate) isCandidate,
  required bool Function(CivilDate) succeeded,
}) {
  var current = 0;
  for (var d = asOf;; d = d.addDays(-1)) {
    if (asOf.addDays(-lookbackDays).isAfter(d)) break;
    if (!isCandidate(d)) continue;
    if (succeeded(d)) {
      current++;
    } else if (d == asOf) {
      continue; // grace: the reference day still has time to be completed
    } else {
      break;
    }
  }

  var run = 0;
  var longest = 0;
  final start = asOf.addDays(-lookbackDays);
  for (var d = start; !d.isAfter(asOf); d = d.addDays(1)) {
    if (!isCandidate(d)) continue;
    if (succeeded(d)) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }

  return StreakInfo(current: current, longest: longest);
}
