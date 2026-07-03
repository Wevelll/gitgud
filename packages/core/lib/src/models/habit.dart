import '../time/civil_date.dart';

/// Whether a habit is one to build up or one to cut down. Purely for the UI's
/// framing (and target semantics: a target is a goal for [good], a cap for
/// [bad]); the counting math is identical either way.
enum HabitPolarity { good, bad }

/// A countable habit with no fixed time (SPEC §3 extension): press to increment
/// its tally for the day. Water, push-ups (good) or cigarettes (bad).
///
/// The habit is the definition; the *count* lives in append-only [HabitEvent]s
/// so history is preserved and undo is just dropping the last event.
class Habit {
  const Habit({
    required this.id,
    required this.label,
    required this.colorHex,
    required this.createdAt,
    this.polarity = HabitPolarity.good,
    this.dailyTarget,
    this.archived = false,
  });

  final String id;
  final String label;
  final String colorHex;

  /// ISO-8601 timestamp of creation.
  final String createdAt;
  final HabitPolarity polarity;

  /// Optional per-day goal ([HabitPolarity.good]) or cap ([HabitPolarity.bad]).
  final int? dailyTarget;
  final bool archived;

  Habit copyWith({
    String? id,
    String? label,
    String? colorHex,
    String? createdAt,
    HabitPolarity? polarity,
    int? dailyTarget,
    bool? archived,
  }) {
    return Habit(
      id: id ?? this.id,
      label: label ?? this.label,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      polarity: polarity ?? this.polarity,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      archived: archived ?? this.archived,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Habit &&
      other.id == id &&
      other.label == label &&
      other.colorHex == colorHex &&
      other.createdAt == createdAt &&
      other.polarity == polarity &&
      other.dailyTarget == dailyTarget &&
      other.archived == archived;

  @override
  int get hashCode => Object.hash(
      id, label, colorHex, createdAt, polarity, dailyTarget, archived);
}

/// One occurrence of a habit — an append-only "press" tallied to a [date].
class HabitEvent {
  const HabitEvent({
    required this.id,
    required this.habitId,
    required this.date,
    required this.ts,
  });

  final String id;
  final String habitId;
  final CivilDate date;

  /// ISO-8601 timestamp of the press.
  final String ts;

  @override
  bool operator ==(Object other) =>
      other is HabitEvent &&
      other.id == id &&
      other.habitId == habitId &&
      other.date == date &&
      other.ts == ts;

  @override
  int get hashCode => Object.hash(id, habitId, date, ts);
}

/// A habit paired with its count (and target) for a given date — the shape the
/// UI and MCP `get_habits` consume.
class HabitDayCount {
  const HabitDayCount({
    required this.habit,
    required this.count,
  });

  final Habit habit;
  final int count;

  int? get target => habit.dailyTarget;

  /// True when a [target] is set and it's been met — reaching the goal for a
  /// good habit, or hitting the cap for a bad one.
  bool get targetReached => target != null && count >= target!;
}

/// Counts events for [habitId] on [date].
int habitCountOn(
  CivilDate date,
  String habitId,
  Iterable<HabitEvent> events,
) {
  var n = 0;
  for (final e in events) {
    if (e.habitId == habitId && e.date == date) n++;
  }
  return n;
}

/// Builds the day's habit list: every non-archived habit with its count on
/// [date]. Scans [events] once into per-habit tallies (O(habits + events)).
List<HabitDayCount> habitCountsFor(
  CivilDate date,
  Iterable<Habit> habits,
  Iterable<HabitEvent> events,
) {
  final counts = <String, int>{};
  for (final e in events) {
    if (e.date == date) {
      counts[e.habitId] = (counts[e.habitId] ?? 0) + 1;
    }
  }
  return [
    for (final h in habits)
      if (!h.archived) HabitDayCount(habit: h, count: counts[h.id] ?? 0),
  ];
}
