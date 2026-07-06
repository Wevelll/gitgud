import '../models/day_profile.dart';
import '../models/habit.dart';
import '../models/recurrence.dart';
import '../models/recurring_task.dart';
import '../models/ring_edit.dart';
import '../models/segment.dart';
import '../models/sub_block.dart';
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

  /// The effective ring for [date]: its per-date override, else the template
  /// assigned to that weekday, else the default (see [effectiveProfile]).
  DayProfile profileForDate(CivilDate date);

  /// Switches the active profile. Throws [StateError] if unknown.
  void switchProfile(String profileId);

  /// Adds a profile (a weekday template or a per-date override). Throws
  /// [StateError] if its id already exists.
  void addProfile(DayProfile profile);

  /// Removes profile [id] (and any sub-blocks under its segments). Throws
  /// [StateError] if unknown, if it's the active profile, or if it's the last
  /// one.
  void removeProfile(String id);

  /// Renames a profile. Throws [StateError] if unknown.
  void setProfileName(String id, String name);

  /// Sets which weekdays a template applies to (bitmask, Monday = bit 0).
  /// Throws [StateError] if unknown.
  void setProfileWeekdays(String id, int activeDaysMask);

  /// Makes [id] the sole default template (clears the flag on the others).
  /// Throws [StateError] if unknown.
  void setDefaultProfile(String id);

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

  /// The sparse sub-block overlay: parent-segment id → its sub-blocks (SPEC §2
  /// nested detail).
  SubBlockPlan subBlocks();

  /// Adds a sub-block inside [parentId] (a segment of the active profile) and
  /// returns the created span. Throws [StateError] if the parent is unknown to
  /// the active profile, or [InvalidSubBlockException] if the result would fall
  /// outside the parent or overlap a sibling.
  Segment addSubBlock({
    required String parentId,
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  });

  /// Updates a sub-block's name/color/bounds; returns the updated span. Throws
  /// [StateError] if unknown, or [InvalidSubBlockException] if invalid.
  Segment updateSubBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  });

  /// Removes the sub-block [id]. Throws [StateError] if unknown.
  void deleteSubBlock(String id);

  List<RecurringTask> tasks();
  List<TaskCompletion> completions();

  RecurringTask addRecurringTask({
    required String label,
    required Recurrence recurrence,
    required String colorHex,
  });

  /// Updates a task's label, color, and/or recurrence; returns the updated
  /// task. Throws [StateError] if no such task.
  RecurringTask updateRecurringTask(
    String id, {
    String? label,
    String? colorHex,
    Recurrence? recurrence,
  });

  /// Archives or un-archives a task. An archived task keeps its completion
  /// history but no longer appears in the tray ([RecurringTask.isDueOn] is
  /// false). Throws [StateError] if no such task.
  void setTaskArchived(String id, {required bool archived});

  /// Permanently removes a task and its completion history. Throws
  /// [StateError] if no such task.
  void deleteRecurringTask(String id);

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

  /// Replaces **all** state with [snapshot] (import / sync-apply). The single-
  /// writer sync model uses this; concurrent-edit merging (CRDT) is future work.
  void restore(DaySnapshot snapshot);
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
    repo._loadSubBlocks(snapshot.subBlocks);
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
  // Sparse sub-block overlay: parent-segment id → growable list of sub-blocks.
  final Map<String, List<Segment>> _subBlocks = {};

  static String Function() _sequentialIds() {
    var n = 0;
    return () => 'id${++n}';
  }

  @override
  DayProfile activeProfile() => _profiles[_activeId]!;

  @override
  List<DayProfile> profiles() => _profiles.values.toList(growable: false);

  @override
  DayProfile profileForDate(CivilDate date) =>
      effectiveProfile(date, _profiles.values);

  @override
  void switchProfile(String profileId) {
    if (!_profiles.containsKey(profileId)) {
      throw StateError('No profile "$profileId"');
    }
    _activeId = profileId;
  }

  @override
  void addProfile(DayProfile profile) {
    if (_profiles.containsKey(profile.id)) {
      throw StateError('Profile "${profile.id}" already exists');
    }
    _profiles[profile.id] = profile;
  }

  @override
  void removeProfile(String id) {
    final profile = _profiles[id];
    if (profile == null) throw StateError('No profile "$id"');
    if (id == _activeId) throw StateError('Cannot remove the active profile');
    if (_profiles.length <= 1)
      throw StateError('Cannot remove the last profile');
    _profiles.remove(id);
    for (final s in profile.segments) {
      _subBlocks.remove(s.id); // drop this profile's sub-blocks
    }
  }

  void _mutateProfile(String id, DayProfile Function(DayProfile) f) {
    final p = _profiles[id];
    if (p == null) throw StateError('No profile "$id"');
    _profiles[id] = f(p);
  }

  @override
  void setProfileName(String id, String name) =>
      _mutateProfile(id, (p) => p.copyWith(name: name));

  @override
  void setProfileWeekdays(String id, int activeDaysMask) =>
      _mutateProfile(id, (p) => p.copyWith(activeDaysMask: activeDaysMask));

  @override
  void setDefaultProfile(String id) {
    if (!_profiles.containsKey(id)) throw StateError('No profile "$id"');
    for (final key in _profiles.keys.toList()) {
      _profiles[key] = _profiles[key]!.copyWith(isDefault: key == id);
    }
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
    _reconcileSubBlocks();
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
    _reconcileSubBlocks();
    return updated.segments.firstWhere((s) => s.id == id);
  }

  @override
  void deleteBlock(String id) {
    _profiles[_activeId] = activeProfile().deleteBlock(id);
    _reconcileSubBlocks();
  }

  // ---- sub-blocks -----------------------------------------------------------

  @override
  SubBlockPlan subBlocks() => SubBlockPlan(_subBlocks);

  /// The active profile's segment [parentId], or a [StateError] if it isn't one.
  Segment _activeSegment(String parentId) {
    final match = activeProfile().segments.where((s) => s.id == parentId);
    if (match.isEmpty) {
      throw StateError('No segment "$parentId" in the active profile');
    }
    return match.first;
  }

  /// Locates a sub-block by id, returning its parent id and index, or throws.
  ({String parentId, int index}) _locateSubBlock(String id) {
    for (final entry in _subBlocks.entries) {
      final i = entry.value.indexWhere((s) => s.id == id);
      if (i != -1) return (parentId: entry.key, index: i);
    }
    throw StateError('No sub-block "$id"');
  }

  @override
  Segment addSubBlock({
    required String parentId,
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final parent = _activeSegment(parentId);
    final child = Segment(
      id: _idFactory(),
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    final siblings = _subBlocks[parentId] ?? const [];
    validateSubBlocks(parent, [...siblings, child]); // throws if illegal
    (_subBlocks[parentId] ??= []).add(child);
    return child;
  }

  @override
  Segment updateSubBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    final at = _locateSubBlock(id);
    final parent = _activeSegment(at.parentId);
    final list = _subBlocks[at.parentId]!;
    final updated = list[at.index].copyWith(
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    final siblings = [
      for (var i = 0; i < list.length; i++)
        if (i == at.index) updated else list[i],
    ];
    validateSubBlocks(parent, siblings); // throws if illegal
    list[at.index] = updated;
    return updated;
  }

  @override
  void deleteSubBlock(String id) {
    final at = _locateSubBlock(id);
    final list = _subBlocks[at.parentId]!..removeAt(at.index);
    if (list.isEmpty) _subBlocks.remove(at.parentId);
  }

  /// Re-fits the overlay after a ring edit (clip cascade / drop vanished).
  void _reconcileSubBlocks() {
    final fitted = reconcileSubBlocks(activeProfile(), _subBlocks);
    _subBlocks
      ..clear()
      ..addEntries(fitted.entries.map((e) => MapEntry(e.key, [...e.value])));
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
  RecurringTask updateRecurringTask(
    String id, {
    String? label,
    String? colorHex,
    Recurrence? recurrence,
  }) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) throw StateError('No task "$id"');
    final updated = _tasks[i].copyWith(
      label: label,
      colorHex: colorHex,
      recurrence: recurrence,
    );
    _tasks[i] = updated;
    return updated;
  }

  @override
  void setTaskArchived(String id, {required bool archived}) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) throw StateError('No task "$id"');
    _tasks[i] = _tasks[i].copyWith(archived: archived);
  }

  @override
  void deleteRecurringTask(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) throw StateError('No task "$id"');
    _tasks.removeAt(i);
    // Parity with the SQLite store's task_completions ON DELETE CASCADE.
    _completions.removeWhere((c) => c.taskId == id);
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
        subBlocks: {
          for (final e in _subBlocks.entries) e.key: List.unmodifiable(e.value),
        },
      );

  @override
  void restore(DaySnapshot snapshot) {
    _profiles
      ..clear()
      ..addEntries(snapshot.profiles.map((p) => MapEntry(p.id, p)));
    _activeId = snapshot.activeProfileId;
    _tasks
      ..clear()
      ..addAll(snapshot.tasks);
    _completions
      ..clear()
      ..addAll(snapshot.completions);
    _logs
      ..clear()
      ..addAll(snapshot.logs);
    _habits
      ..clear()
      ..addAll(snapshot.habits);
    _habitEvents
      ..clear()
      ..addAll(snapshot.habitEvents);
    _loadSubBlocks(snapshot.subBlocks);
  }

  void _loadSubBlocks(Map<String, List<Segment>> plan) {
    _subBlocks
      ..clear()
      ..addEntries(plan.entries.map((e) => MapEntry(e.key, [...e.value])));
  }
}
