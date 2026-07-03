import 'package:day_dial_core/day_dial_core.dart';

/// State access + mutation for a single user's day, expressed in `core` types.
///
/// Both the MCP tools and (eventually) the Flutter app talk to this interface;
/// the concrete store (in-memory here, SQLite later) lives behind it. All
/// business logic stays in `core` — the repository just holds state and calls
/// core operations.
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

  List<TimeLog> logs();

  TimeLog logActual({
    required String category,
    required String startTs,
    required String endTs,
    String? segmentId,
    String? note,
    LogSource source,
  });
}

/// In-memory [DayRepository]. Deterministic when given a fixed [idFactory] and
/// [clock], which is what the tests rely on.
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

  final Map<String, DayProfile> _profiles;
  String _activeId;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  final List<RecurringTask> _tasks = [];
  final List<TaskCompletion> _completions = [];
  final List<TimeLog> _logs = [];

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
}
