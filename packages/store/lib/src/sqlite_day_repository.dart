import 'package:day_dial_core/day_dial_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// A [DayRepository] backed by a local SQLite database (SPEC §5), so a user's
/// day survives restarts.
///
/// It owns no business logic — every edit delegates to `core` (ring math,
/// validation) and this class only reads/writes rows. A profile is persisted as
/// its `profiles` row plus its `segments` rows; a ring edit re-materializes the
/// whole segment set for that profile (cheap; a day has a handful of segments).
class SqliteDayRepository implements DayRepository {
  SqliteDayRepository._(this._db, this._idFactory, this._clock);

  final Database _db;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  /// Opens (creating if needed) a database at [path], or an in-memory one when
  /// [path] is null. If the database has no profiles yet, [seedIfEmpty] is
  /// inserted as first-run defaults and the default/first becomes active.
  factory SqliteDayRepository.open({
    String? path,
    List<DayProfile> seedIfEmpty = const [],
    String Function()? idFactory,
    DateTime Function()? clock,
  }) {
    final db = path == null ? sqlite3.openInMemory() : sqlite3.open(path);
    final repo = SqliteDayRepository._(
      db,
      idFactory ?? _defaultIds(),
      clock ?? DateTime.now,
    );
    repo._migrate();
    repo._seedIfEmpty(seedIfEmpty);
    return repo;
  }

  /// Releases the database handle.
  void close() => _db.dispose();

  /// Default id generator: a per-open time base plus a counter, so ids stay
  /// unique **across restarts** (a plain 1,2,3 sequence would collide with ids
  /// already persisted from a previous run). Tests inject a deterministic one.
  static String Function() _defaultIds() {
    var n = 0;
    final base = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return () => '$base-${n++}';
  }

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    for (final stmt in schemaStatements) {
      _db.execute(stmt);
    }
    _setSetting('schema_version', '$schemaVersion');
  }

  void _seedIfEmpty(List<DayProfile> seed) {
    if (seed.isEmpty) return;
    final count = _db.select('SELECT COUNT(*) AS c FROM profiles').first['c'];
    if ((count as int) > 0) return;
    for (final p in seed) {
      _insertProfile(p);
    }
    final active =
        seed.firstWhere((p) => p.isDefault, orElse: () => seed.first);
    _setSetting('active_profile_id', active.id);
  }

  // ---- settings -------------------------------------------------------------

  void _setSetting(String key, String value) => _db.execute(
        'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
        [key, value],
      );

  String? _getSetting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  String get _activeId {
    final id = _getSetting('active_profile_id');
    if (id == null) throw StateError('No active profile set');
    return id;
  }

  // ---- profiles / segments --------------------------------------------------

  void _insertProfile(DayProfile p) {
    _db.execute(
      'INSERT INTO profiles (id, name, active_days_mask, is_default) '
      'VALUES (?, ?, ?, ?)',
      [p.id, p.name, p.activeDaysMask, p.isDefault ? 1 : 0],
    );
    _writeSegments(p);
  }

  /// Replaces the persisted segments for [p] with its current ring.
  void _writeSegments(DayProfile p) {
    _db.execute('DELETE FROM segments WHERE profile_id = ?', [p.id]);
    var order = 0;
    for (final s in p.segments) {
      _db.execute(
        'INSERT INTO segments '
        '(id, profile_id, start_min, end_min, name, color, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [s.id, p.id, s.startMin, s.endMin, s.name, s.colorHex, order++],
      );
    }
  }

  DayProfile _loadProfile(String id) {
    final prows = _db.select('SELECT * FROM profiles WHERE id = ?', [id]);
    if (prows.isEmpty) throw StateError('No profile "$id"');
    final p = prows.first;
    final segRows = _db.select(
      'SELECT * FROM segments WHERE profile_id = ? ORDER BY sort_order',
      [id],
    );
    final segments = [
      for (final s in segRows)
        Segment(
          id: s['id'] as String,
          name: s['name'] as String,
          colorHex: s['color'] as String,
          startMin: s['start_min'] as int,
          endMin: s['end_min'] as int,
        )
    ];
    return DayProfile(
      id: p['id'] as String,
      name: p['name'] as String,
      segments: segments,
      activeDaysMask: p['active_days_mask'] as int,
      isDefault: (p['is_default'] as int) == 1,
    );
  }

  @override
  DayProfile activeProfile() => _loadProfile(_activeId);

  @override
  List<DayProfile> profiles() {
    final ids = _db.select('SELECT id FROM profiles');
    return [for (final r in ids) _loadProfile(r['id'] as String)];
  }

  @override
  void switchProfile(String profileId) {
    final exists =
        _db.select('SELECT 1 FROM profiles WHERE id = ?', [profileId]);
    if (exists.isEmpty) throw StateError('No profile "$profileId"');
    _setSetting('active_profile_id', profileId);
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
    _writeSegments(updated);
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
    _writeSegments(updated);
    return updated.segments.firstWhere((s) => s.id == id);
  }

  @override
  void deleteBlock(String id) {
    _writeSegments(activeProfile().deleteBlock(id));
  }

  // ---- recurring tasks ------------------------------------------------------

  @override
  List<RecurringTask> tasks() {
    final rows = _db.select('SELECT * FROM recurring_tasks');
    return [
      for (final r in rows)
        RecurringTask(
          id: r['id'] as String,
          label: r['label'] as String,
          colorHex: r['color'] as String,
          recurrence: Recurrence.parse(r['recurrence_rule'] as String),
          createdAt: r['created_at'] as String,
          archived: (r['archived'] as int) == 1,
        )
    ];
  }

  @override
  List<TaskCompletion> completions() {
    final rows = _db.select('SELECT * FROM task_completions');
    return [
      for (final r in rows)
        TaskCompletion(
          id: r['id'] as String,
          taskId: r['task_id'] as String,
          date: CivilDate.parse(r['date'] as String),
          completedAt: r['completed_at'] as String,
        )
    ];
  }

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
    _db.execute(
      'INSERT INTO recurring_tasks '
      '(id, label, color, recurrence_rule, created_at, archived) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      [
        task.id,
        task.label,
        task.colorHex,
        task.recurrence.encode(),
        task.createdAt,
      ],
    );
    return task;
  }

  @override
  void completeTask(String taskId, CivilDate date) {
    final exists =
        _db.select('SELECT 1 FROM recurring_tasks WHERE id = ?', [taskId]);
    if (exists.isEmpty) throw StateError('No task "$taskId"');
    // UNIQUE(task_id, date) + OR IGNORE makes this idempotent per (task, date).
    _db.execute(
      'INSERT OR IGNORE INTO task_completions '
      '(id, task_id, date, completed_at) VALUES (?, ?, ?, ?)',
      [_idFactory(), taskId, date.iso, _clock().toUtc().toIso8601String()],
    );
  }

  @override
  void uncompleteTask(String taskId, CivilDate date) {
    _db.execute(
      'DELETE FROM task_completions WHERE task_id = ? AND date = ?',
      [taskId, date.iso],
    );
  }

  // ---- time logs ------------------------------------------------------------

  @override
  List<TimeLog> logs() {
    final rows = _db.select('SELECT * FROM time_logs');
    return [
      for (final r in rows)
        TimeLog(
          id: r['id'] as String,
          date: CivilDate.parse(r['date'] as String),
          startTs: r['start_ts'] as String,
          endTs: r['end_ts'] as String,
          category: r['category'] as String,
          segmentId: r['segment_id'] as String?,
          note: r['note'] as String?,
          source: _parseSource(r['source'] as String),
        )
    ];
  }

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
    _db.execute(
      'INSERT INTO time_logs '
      '(id, date, start_ts, end_ts, category, segment_id, note, source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        log.id,
        log.date.iso,
        log.startTs,
        log.endTs,
        log.category,
        log.segmentId,
        log.note,
        log.source.name,
      ],
    );
    return log;
  }

  static LogSource _parseSource(String s) => LogSource.values
      .firstWhere((v) => v.name == s, orElse: () => LogSource.manual);
}
