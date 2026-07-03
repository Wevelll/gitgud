import '../time/civil_date.dart';
import 'recurrence.dart';

/// A "must-do today" untimed task (SPEC §3) — lives in a tray, not on the dial.
class RecurringTask {
  const RecurringTask({
    required this.id,
    required this.label,
    required this.colorHex,
    required this.recurrence,
    required this.createdAt,
    this.archived = false,
  });

  final String id;
  final String label;
  final String colorHex;
  final Recurrence recurrence;

  /// ISO-8601 timestamp string of creation.
  final String createdAt;
  final bool archived;

  /// Whether this task belongs in the tray on [date] (active + rule matches).
  bool isDueOn(CivilDate date) => !archived && recurrence.isDueOn(date);

  RecurringTask copyWith({
    String? id,
    String? label,
    String? colorHex,
    Recurrence? recurrence,
    String? createdAt,
    bool? archived,
  }) {
    return RecurringTask(
      id: id ?? this.id,
      label: label ?? this.label,
      colorHex: colorHex ?? this.colorHex,
      recurrence: recurrence ?? this.recurrence,
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecurringTask &&
      other.id == id &&
      other.label == label &&
      other.colorHex == colorHex &&
      other.recurrence == recurrence &&
      other.createdAt == createdAt &&
      other.archived == archived;

  @override
  int get hashCode =>
      Object.hash(id, label, colorHex, recurrence, createdAt, archived);
}

/// A record that a task was completed on a given date (SPEC §5
/// `task_completions`). Completion is per-date, not per-instance.
class TaskCompletion {
  const TaskCompletion({
    required this.id,
    required this.taskId,
    required this.date,
    required this.completedAt,
  });

  final String id;
  final String taskId;
  final CivilDate date;

  /// ISO-8601 timestamp string of when it was checked off.
  final String completedAt;

  @override
  bool operator ==(Object other) =>
      other is TaskCompletion &&
      other.id == id &&
      other.taskId == taskId &&
      other.date == date &&
      other.completedAt == completedAt;

  @override
  int get hashCode => Object.hash(id, taskId, date, completedAt);
}

/// A task paired with its completion state for a specific date — the shape the
/// tray UI and MCP `get_recurring_tasks` consume.
class TrayItem {
  const TrayItem({required this.task, required this.doneToday});
  final RecurringTask task;
  final bool doneToday;
}

/// Builds the tray for [date]: every non-archived task whose rule fires that
/// day, paired with whether a completion exists for it on that date.
///
/// [completions] is scanned once into a `taskId` set filtered to [date], so
/// this is O(tasks + completions).
List<TrayItem> trayFor(
  CivilDate date,
  Iterable<RecurringTask> tasks,
  Iterable<TaskCompletion> completions,
) {
  final doneIds = <String>{
    for (final c in completions)
      if (c.date == date) c.taskId,
  };
  return [
    for (final t in tasks)
      if (t.isDueOn(date)) TrayItem(task: t, doneToday: doneIds.contains(t.id)),
  ];
}
