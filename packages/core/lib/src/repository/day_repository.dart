import '../models/day_profile.dart';
import '../models/habit.dart';
import '../models/recurrence.dart';
import '../models/recurring_task.dart';
import '../models/ring_edit.dart';
import '../models/segment.dart';
import '../models/time_log.dart';
import '../time/civil_date.dart';
import 'day_snapshot.dart';

/// State access + mutation for a single user's day, expressed in `core` types.
///
/// This is the app's data seam: both the MCP tools and the Flutter UI talk to
/// this interface, and the concrete store (in-memory here, SQLite in
/// `packages/store`) lives behind it. It stays in `core` — and stays
/// platform-agnostic — because it holds no I/O itself; all business logic is
/// core operations, all persistence is an implementation detail behind it.
abstract interface class DayRepository {
  DayProfile activeProfile();
  List<DayProfile> profiles();

  /// Switches the active profile. Throws [StateError] if unknown.
  void switchProfile(String profileId);

  /// Adds a block to the active profile and returns the created segment.
  Segment addBlock({
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  });

  /// Updates a block in the active profile; returns the updated segment.
  Segment updateBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  });

  void deleteBlock(String id);

  List<RecurringTask> tasks();
  List<TaskCompletion> completions();

  RecurringTask addRecurringTask({
    required String label,
    required Recurrence recurrence,
    required String colorHex,
  });

  /// Marks [taskId] done on [date]; idempotent per (task, date).
  void completeTask(String taskId, CivilDate date);

  /// Removes the completion for [taskId] on [date], if any (un-checks it).
  void uncompleteTask(String taskId, CivilDate date);

  List<TimeLog> logs();

  TimeLog logActual({
    required String category,
    required String startTs,
    required String endTs,
    String? segmentId,
    String? note,
    LogSource source,
  });

  List<Habit> habits();
  List<HabitEvent> habitEvents();

  Habit addHabit({
    required String label,
    required String colorHex,
    HabitPolarity polarity,
    int? dailyTarget,
  });

  /// Records one occurrence of [habitId] on [date] (default: today). Returns
  /// the appended event.
  HabitEvent incrementHabit(String habitId, {CivilDate? date});

  /// Removes the most recent occurrence of [habitId] on [date], if any. Returns
  /// whether one was removed (so a count can't go below zero).
  bool decrementHabit(String habitId, CivilDate date);

  /// A full, serializable snapshot of current state — the sync/export unit.
  DaySnapshot snapshot();
}

/// In-memory [DayRepository]. Platform-agnostic (no I/O), and deterministic
/// when given a fixed [idFactory] and [clock] — which is what tests rely on.
class InMemoryDayRepository implements DayRepository {
  InMemoryDayRepository({
    required List<DayProfile> profiles,
    String? activeProfileId,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _profiles = {for (final p in profiles) p.id: p},
        _activeId = activeProfileId ??
            (profiles.firstWhere((p) => p.isDefault,
                orElse: () => profiles.first)).id,
        _idFactory = idFactory ?? _sequentialIds(),
        _clock = clock ?? DateTime.now {
    if (profiles.isEmpty) {
      throw ArgumentError('At least one profile is required');
    }
  }

  /// Rebuilds an in-memory repository from a [DaySnapshot] (e.g. hydrated from
  /// the desktop hub over HTTP).
  factory InMemoryDayRepository.fromSnapshot(
    DaySnapshot snapshot, {
    String Function()? idFactory,
    DateTime Function()? clock,
  }) {
    final repo = InMemoryDayRepository(
      profiles: snapshot.profiles,
      activeProfileId: snapshot.activeProfileId,
      idFactory: idFactory,
      clock: clock,
    );
    repo._tasks.addAll(snapshot.tasks);
    repo._completions.addAll(snapshot.completions);
    repo._logs.addAll(snapshot.logs);
    repo._habits.addAll(snapshot.habits);
    repo._habitEvents.addAll(snapshot.habitEvents);
    return repo;
  }

  final Map<String, DayProfile> _profiles;
  String _activeId;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  final List<RecurringTask> _tasks = [];
  final List<TaskCompletion> _completions = [];
  final List<TimeLog> _logs = [];
  final List<Habit> _habits = [];
  final List<HabitEvent> _habitEvents = [];

  static String Function() _sequentialIds() {
    var n = 0;
    return () => 'id${++n}';
  }

  @override
  DayProfile activeProfile() => _profiles[_activeId]!;

  @override
  List<DayProfile> profiles() => _profiles.values.toList(growable: false);

  @override
  void switchProfile(String profileId) {
    if (!_profiles.containsKey(profileId)) {
      throw StateError('No profile "$profileId"');
    }
    _activeId = profileId;
  }

  @override
  Segment addBlock({
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final id = _idFactory();
    final updated = activeProfile().addBlock(
      id: id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _profiles[_activeId] = updated;
    return updated.segments.firstWhere((s) => s.id == id);
  }

  @override
  Segment updateBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    final updated = activeProfile().updateBlock(
      id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _profiles[_activeId] = updated;
    return updated.segments.firstWhere((s) => s.id == id);
  }

  @override
  void deleteBlock(String id) {
    _profiles[_activeId] = activeProfile().deleteBlock(id);
  }

  @override
  List<RecurringTask> tasks() => List.unmodifiable(_tasks);

  @override
  List<TaskCompletion> completions() => List.unmodifiable(_completions);

  @override
  RecurringTask addRecurringTask({
    required String label,
    required Recurrence recurrence,
    required String colorHex,
  }) {
    final task = RecurringTask(
      id: _idFactory(),
      label: label,
      colorHex: colorHex,
      recurrence: recurrence,
      createdAt: _clock().toUtc().toIso8601String(),
    );
    _tasks.add(task);
    return task;
  }

  @override
  void completeTask(String taskId, CivilDate date) {
    if (!_tasks.any((t) => t.id == taskId)) {
      throw StateError('No task "$taskId"');
    }
    final already =
        _completions.any((c) => c.taskId == taskId && c.date == date);
    if (already) return; // idempotent
    _completions.add(TaskCompletion(
      id: _idFactory(),
      taskId: taskId,
      date: date,
      completedAt: _clock().toUtc().toIso8601String(),
    ));
  }

  @override
  void uncompleteTask(String taskId, CivilDate date) {
    _completions.removeWhere((c) => c.taskId == taskId && c.date == date);
  }

  @override
  List<TimeLog> logs() => List.unmodifiable(_logs);

  @override
  TimeLog logActual({
    required String category,
    required String startTs,
    required String endTs,
    String? segmentId,
    String? note,
    LogSource source = LogSource.manual,
  }) {
    final log = TimeLog(
      id: _idFactory(),
      date: CivilDate.fromDateTime(DateTime.parse(startTs)),
      startTs: startTs,
      endTs: endTs,
      category: category,
      segmentId: segmentId,
      note: note,
      source: source,
    );
    _logs.add(log);
    return log;
  }

  @override
  List<Habit> habits() => List.unmodifiable(_habits);

  @override
  List<HabitEvent> habitEvents() => List.unmodifiable(_habitEvents);

  @override
  Habit addHabit({
    required String label,
    required String colorHex,
    HabitPolarity polarity = HabitPolarity.good,
    int? dailyTarget,
  }) {
    final habit = Habit(
      id: _idFactory(),
      label: label,
      colorHex: colorHex,
      createdAt: _clock().toUtc().toIso8601String(),
      polarity: polarity,
      dailyTarget: dailyTarget,
    );
    _habits.add(habit);
    return habit;
  }

  @override
  HabitEvent incrementHabit(String habitId, {CivilDate? date}) {
    if (!_habits.any((h) => h.id == habitId)) {
      throw StateError('No habit "$habitId"');
    }
    final now = _clock();
    final event = HabitEvent(
      id: _idFactory(),
      habitId: habitId,
      date: date ?? CivilDate.fromDateTime(now),
      ts: now.toUtc().toIso8601String(),
    );
    _habitEvents.add(event);
    return event;
  }

  @override
  bool decrementHabit(String habitId, CivilDate date) {
    for (var i = _habitEvents.length - 1; i >= 0; i--) {
      final e = _habitEvents[i];
      if (e.habitId == habitId && e.date == date) {
        _habitEvents.removeAt(i);
        return true;
      }
    }
    return false;
  }

  @override
  DaySnapshot snapshot() => DaySnapshot(
        profiles: profiles(),
        activeProfileId: _activeId,
        tasks: tasks(),
        completions: completions(),
        logs: logs(),
        habits: habits(),
        habitEvents: habitEvents(),
      );
}
