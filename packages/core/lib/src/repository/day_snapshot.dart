import '../models/day_profile.dart';
import '../models/habit.dart';
import '../models/recurrence.dart';
import '../models/recurring_task.dart';
import '../models/segment.dart';
import '../models/time_log.dart';
import '../time/civil_date.dart';

/// A complete, serializable snapshot of a user's day-state — the wire format for
/// the web companion syncing with the desktop hub (SPEC §8), and the natural
/// unit for backup/export. JSON round-trips losslessly via [toJson]/[fromJson].
class DaySnapshot {
  const DaySnapshot({
    required this.profiles,
    required this.activeProfileId,
    required this.tasks,
    required this.completions,
    required this.logs,
    required this.habits,
    required this.habitEvents,
  });

  final List<DayProfile> profiles;
  final String activeProfileId;
  final List<RecurringTask> tasks;
  final List<TaskCompletion> completions;
  final List<TimeLog> logs;
  final List<Habit> habits;
  final List<HabitEvent> habitEvents;

  Map<String, Object?> toJson() => {
        'activeProfileId': activeProfileId,
        'profiles': [for (final p in profiles) _profileToJson(p)],
        'tasks': [for (final t in tasks) _taskToJson(t)],
        'completions': [for (final c in completions) _completionToJson(c)],
        'logs': [for (final l in logs) _logToJson(l)],
        'habits': [for (final h in habits) _habitToJson(h)],
        'habitEvents': [for (final e in habitEvents) _habitEventToJson(e)],
      };

  factory DaySnapshot.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) =>
        ((json[key] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, Object?>())
            .toList();
    return DaySnapshot(
      activeProfileId: json['activeProfileId'] as String,
      profiles: [for (final p in list('profiles')) _profileFromJson(p)],
      tasks: [for (final t in list('tasks')) _taskFromJson(t)],
      completions: [
        for (final c in list('completions')) _completionFromJson(c)
      ],
      logs: [for (final l in list('logs')) _logFromJson(l)],
      habits: [for (final h in list('habits')) _habitFromJson(h)],
      habitEvents: [
        for (final e in list('habitEvents')) _habitEventFromJson(e)
      ],
    );
  }

  // ---- per-model codecs -----------------------------------------------------

  static Map<String, Object?> _profileToJson(DayProfile p) => {
        'id': p.id,
        'name': p.name,
        'activeDaysMask': p.activeDaysMask,
        'isDefault': p.isDefault,
        'segments': [
          for (final s in p.segments)
            {
              'id': s.id,
              'name': s.name,
              'color': s.colorHex,
              'start': s.startMin,
              'end': s.endMin,
            }
        ],
      };

  static DayProfile _profileFromJson(Map<String, Object?> j) => DayProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        activeDaysMask: (j['activeDaysMask'] as num?)?.toInt() ?? 0,
        isDefault: j['isDefault'] as bool? ?? false,
        segments: [
          for (final s in (j['segments'] as List).cast<Map<String, Object?>>())
            Segment(
              id: s['id'] as String,
              name: s['name'] as String,
              colorHex: s['color'] as String,
              startMin: (s['start'] as num).toInt(),
              endMin: (s['end'] as num).toInt(),
            )
        ],
      );

  static Map<String, Object?> _taskToJson(RecurringTask t) => {
        'id': t.id,
        'label': t.label,
        'color': t.colorHex,
        'recurrence': t.recurrence.encode(),
        'createdAt': t.createdAt,
        'archived': t.archived,
      };

  static RecurringTask _taskFromJson(Map<String, Object?> j) => RecurringTask(
        id: j['id'] as String,
        label: j['label'] as String,
        colorHex: j['color'] as String,
        recurrence: Recurrence.parse(j['recurrence'] as String),
        createdAt: j['createdAt'] as String,
        archived: j['archived'] as bool? ?? false,
      );

  static Map<String, Object?> _completionToJson(TaskCompletion c) => {
        'id': c.id,
        'taskId': c.taskId,
        'date': c.date.iso,
        'completedAt': c.completedAt,
      };

  static TaskCompletion _completionFromJson(Map<String, Object?> j) =>
      TaskCompletion(
        id: j['id'] as String,
        taskId: j['taskId'] as String,
        date: CivilDate.parse(j['date'] as String),
        completedAt: j['completedAt'] as String,
      );

  static Map<String, Object?> _logToJson(TimeLog l) => {
        'id': l.id,
        'date': l.date.iso,
        'start': l.startTs,
        'end': l.endTs,
        'category': l.category,
        'segmentId': l.segmentId,
        'note': l.note,
        'source': l.source.name,
      };

  static TimeLog _logFromJson(Map<String, Object?> j) => TimeLog(
        id: j['id'] as String,
        date: CivilDate.parse(j['date'] as String),
        startTs: j['start'] as String,
        endTs: j['end'] as String,
        category: j['category'] as String,
        segmentId: j['segmentId'] as String?,
        note: j['note'] as String?,
        source: LogSource.values.firstWhere((v) => v.name == j['source'],
            orElse: () => LogSource.manual),
      );

  static Map<String, Object?> _habitToJson(Habit h) => {
        'id': h.id,
        'label': h.label,
        'color': h.colorHex,
        'polarity': h.polarity.name,
        'dailyTarget': h.dailyTarget,
        'createdAt': h.createdAt,
        'archived': h.archived,
      };

  static Habit _habitFromJson(Map<String, Object?> j) => Habit(
        id: j['id'] as String,
        label: j['label'] as String,
        colorHex: j['color'] as String,
        polarity: HabitPolarity.values.firstWhere(
            (v) => v.name == j['polarity'],
            orElse: () => HabitPolarity.good),
        dailyTarget: (j['dailyTarget'] as num?)?.toInt(),
        createdAt: j['createdAt'] as String,
        archived: j['archived'] as bool? ?? false,
      );

  static Map<String, Object?> _habitEventToJson(HabitEvent e) => {
        'id': e.id,
        'habitId': e.habitId,
        'date': e.date.iso,
        'ts': e.ts,
      };

  static HabitEvent _habitEventFromJson(Map<String, Object?> j) => HabitEvent(
        id: j['id'] as String,
        habitId: j['habitId'] as String,
        date: CivilDate.parse(j['date'] as String),
        ts: j['ts'] as String,
      );
}
