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
    // v2 -> v3: per-date override column. Guarded so it's a no-op on a fresh
    // database (whose CREATE already includes the column) and idempotent on an
    // existing one.
    _addColumnIfMissing('profiles', 'for_date', 'TEXT');
    _setSetting('schema_version', '$schemaVersion');
  }

  void _addColumnIfMissing(String table, String column, String type) {
    final cols = _db
        .select('PRAGMA table_info($table)')
        .map((r) => r['name'] as String)
        .toSet();
    if (!cols.contains(column)) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
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
      'INSERT INTO profiles (id, name, active_days_mask, is_default, for_date) '
      'VALUES (?, ?, ?, ?, ?)',
      [p.id, p.name, p.activeDaysMask, p.isDefault ? 1 : 0, p.forDate],
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
      forDate: p['for_date'] as String?,
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
  DayProfile profileForDate(CivilDate date) =>
      effectiveProfile(date, profiles());

  @override
  DayProfile templateForDate(CivilDate date) =>
      weekdayTemplateFor(date, profiles());

  @override
  DayProfile overrideForDate(CivilDate date) {
    final existing = _db.select(
      'SELECT id FROM profiles WHERE for_date = ?',
      [date.iso],
    );
    if (existing.isNotEmpty) {
      return _loadProfile(existing.first['id'] as String);
    }

    final base = weekdayTemplateFor(date, profiles());
    final idMap = <String, String>{};
    final segs = <Segment>[];
    for (final s in base.segments) {
      final nid = _idFactory();
      idMap[s.id] = nid;
      segs.add(s.copyWith(id: nid));
    }
    final override = DayProfile(
      id: _idFactory(),
      name: base.name,
      segments: segs,
      forDate: date.iso,
    );
    _insertProfile(override);

    // Inherit the template's sub-blocks under the new segment ids.
    final plan = _loadSubBlockMap();
    for (final entry in idMap.entries) {
      for (final sb in plan[entry.key] ?? const <Segment>[]) {
        _db.execute(
          'INSERT INTO sub_segments '
          '(id, parent_segment_id, start_min, end_min, name, color, sort_order)'
          ' VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            _idFactory(),
            entry.value,
            sb.startMin,
            sb.endMin,
            sb.name,
            sb.colorHex,
            0,
          ],
        );
      }
    }
    return override;
  }

  @override
  void resetDate(CivilDate date) {
    final rows =
        _db.select('SELECT id FROM profiles WHERE for_date = ?', [date.iso]);
    for (final r in rows) {
      final id = r['id'] as String;
      final segIds = _db
          .select('SELECT id FROM segments WHERE profile_id = ?', [id])
          .map((s) => s['id'] as String)
          .toList();
      if (id == _activeIdOrNull) {
        _setSetting(
            'active_profile_id', weekdayTemplateFor(date, profiles()).id);
      }
      _db.execute(
          'DELETE FROM profiles WHERE id = ?', [id]); // cascades segments
      for (final sid in segIds) {
        _db.execute('DELETE FROM sub_segments WHERE parent_segment_id = ?', [
          sid,
        ]);
      }
    }
  }

  String? get _activeIdOrNull => _getSetting('active_profile_id');

  @override
  void switchProfile(String profileId) {
    final exists =
        _db.select('SELECT 1 FROM profiles WHERE id = ?', [profileId]);
    if (exists.isEmpty) throw StateError('No profile "$profileId"');
    _setSetting('active_profile_id', profileId);
  }

  void _requireProfile(String id) {
    if (_db.select('SELECT 1 FROM profiles WHERE id = ?', [id]).isEmpty) {
      throw StateError('No profile "$id"');
    }
  }

  @override
  void addProfile(DayProfile profile) {
    if (_db.select(
        'SELECT 1 FROM profiles WHERE id = ?', [profile.id]).isNotEmpty) {
      throw StateError('Profile "${profile.id}" already exists');
    }
    _insertProfile(profile);
  }

  @override
  void removeProfile(String id) {
    _requireProfile(id);
    if (id == _activeId) throw StateError('Cannot remove the active profile');
    final count =
        _db.select('SELECT COUNT(*) AS c FROM profiles').first['c'] as int;
    if (count <= 1) throw StateError('Cannot remove the last profile');
    final segIds = _db
        .select('SELECT id FROM segments WHERE profile_id = ?', [id])
        .map((r) => r['id'] as String)
        .toList();
    _db.execute('DELETE FROM profiles WHERE id = ?', [id]); // cascades segments
    for (final sid in segIds) {
      _db.execute(
          'DELETE FROM sub_segments WHERE parent_segment_id = ?', [sid]);
    }
  }

  @override
  void setProfileName(String id, String name) {
    _requireProfile(id);
    _db.execute('UPDATE profiles SET name = ? WHERE id = ?', [name, id]);
  }

  @override
  void setProfileWeekdays(String id, int activeDaysMask) {
    _requireProfile(id);
    _db.execute(
      'UPDATE profiles SET active_days_mask = ? WHERE id = ?',
      [activeDaysMask, id],
    );
  }

  @override
  void setDefaultProfile(String id) {
    _requireProfile(id);
    // (id = ?) is 1 for the chosen row and 0 for the rest.
    _db.execute('UPDATE profiles SET is_default = (id = ?)', [id]);
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
    _writeSegments(updated);
    _reconcileSubBlocks();
    return updated.segments.firstWhere((s) => s.id == id);
  }

  @override
  void deleteBlock(String id) {
    _writeSegments(activeProfile().deleteBlock(id));
    _reconcileSubBlocks();
  }

  // ---- sub-blocks -----------------------------------------------------------

  Map<String, List<Segment>> _loadSubBlockMap() {
    final rows = _db.select(
      'SELECT * FROM sub_segments ORDER BY parent_segment_id, sort_order',
    );
    final map = <String, List<Segment>>{};
    for (final r in rows) {
      (map[r['parent_segment_id'] as String] ??= []).add(Segment(
        id: r['id'] as String,
        name: r['name'] as String,
        colorHex: r['color'] as String,
        startMin: r['start_min'] as int,
        endMin: r['end_min'] as int,
      ));
    }
    return map;
  }

  /// Re-materializes the whole sub_segments table from [plan].
  void _writeSubBlocks(Map<String, List<Segment>> plan) {
    _db.execute('DELETE FROM sub_segments');
    for (final entry in plan.entries) {
      var order = 0;
      for (final s in entry.value) {
        _db.execute(
          'INSERT INTO sub_segments '
          '(id, parent_segment_id, start_min, end_min, name, color, sort_order)'
          ' VALUES (?, ?, ?, ?, ?, ?, ?)',
          [s.id, entry.key, s.startMin, s.endMin, s.name, s.colorHex, order++],
        );
      }
    }
  }

  void _reconcileSubBlocks() {
    _writeSubBlocks(reconcileSubBlocks(activeProfile(), _loadSubBlockMap()));
  }

  Segment _activeSegment(String parentId) {
    final match = activeProfile().segments.where((s) => s.id == parentId);
    if (match.isEmpty) {
      throw StateError('No segment "$parentId" in the active profile');
    }
    return match.first;
  }

  @override
  SubBlockPlan subBlocks() => SubBlockPlan(_loadSubBlockMap());

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
    final siblings = _loadSubBlockMap()[parentId] ?? const <Segment>[];
    validateSubBlocks(parent, [...siblings, child]); // throws if illegal
    _db.execute(
      'INSERT INTO sub_segments '
      '(id, parent_segment_id, start_min, end_min, name, color, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        child.id,
        parentId,
        child.startMin,
        child.endMin,
        child.name,
        child.colorHex,
        siblings.length,
      ],
    );
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
    final map = _loadSubBlockMap();
    String? parentId;
    Segment? old;
    for (final entry in map.entries) {
      for (final s in entry.value) {
        if (s.id == id) {
          parentId = entry.key;
          old = s;
        }
      }
    }
    if (old == null) throw StateError('No sub-block "$id"');
    final parent = _activeSegment(parentId!);
    final updated = old.copyWith(
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    final siblings = [
      for (final s in map[parentId]!)
        if (s.id == id) updated else s,
    ];
    validateSubBlocks(parent, siblings); // throws if illegal
    _db.execute(
      'UPDATE sub_segments SET start_min = ?, end_min = ?, name = ?, color = ? '
      'WHERE id = ?',
      [updated.startMin, updated.endMin, updated.name, updated.colorHex, id],
    );
    return updated;
  }

  @override
  void deleteSubBlock(String id) {
    final exists = _db.select('SELECT 1 FROM sub_segments WHERE id = ?', [id]);
    if (exists.isEmpty) throw StateError('No sub-block "$id"');
    _db.execute('DELETE FROM sub_segments WHERE id = ?', [id]);
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

  RecurringTask _loadTask(String id) {
    final rows = _db.select('SELECT * FROM recurring_tasks WHERE id = ?', [id]);
    if (rows.isEmpty) throw StateError('No task "$id"');
    final r = rows.first;
    return RecurringTask(
      id: r['id'] as String,
      label: r['label'] as String,
      colorHex: r['color'] as String,
      recurrence: Recurrence.parse(r['recurrence_rule'] as String),
      createdAt: r['created_at'] as String,
      archived: (r['archived'] as int) == 1,
    );
  }

  @override
  RecurringTask updateRecurringTask(
    String id, {
    String? label,
    String? colorHex,
    Recurrence? recurrence,
  }) {
    final updated = _loadTask(id).copyWith(
      label: label,
      colorHex: colorHex,
      recurrence: recurrence,
    );
    _db.execute(
      'UPDATE recurring_tasks SET label = ?, color = ?, recurrence_rule = ? '
      'WHERE id = ?',
      [updated.label, updated.colorHex, updated.recurrence.encode(), id],
    );
    return updated;
  }

  @override
  void setTaskArchived(String id, {required bool archived}) {
    _loadTask(id); // existence check (throws if unknown)
    _db.execute(
      'UPDATE recurring_tasks SET archived = ? WHERE id = ?',
      [archived ? 1 : 0, id],
    );
  }

  @override
  void deleteRecurringTask(String id) {
    _loadTask(id); // existence check (throws if unknown)
    // task_completions.task_id is ON DELETE CASCADE (foreign_keys = ON), so the
    // task's completions are removed with it.
    _db.execute('DELETE FROM recurring_tasks WHERE id = ?', [id]);
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

  // ---- habits ---------------------------------------------------------------

  @override
  List<Habit> habits() {
    final rows = _db.select('SELECT * FROM habits');
    return [
      for (final r in rows)
        Habit(
          id: r['id'] as String,
          label: r['label'] as String,
          colorHex: r['color'] as String,
          createdAt: r['created_at'] as String,
          polarity: _parsePolarity(r['polarity'] as String),
          dailyTarget: r['daily_target'] as int?,
          archived: (r['archived'] as int) == 1,
        )
    ];
  }

  @override
  List<HabitEvent> habitEvents() {
    final rows = _db.select('SELECT * FROM habit_events');
    return [
      for (final r in rows)
        HabitEvent(
          id: r['id'] as String,
          habitId: r['habit_id'] as String,
          date: CivilDate.parse(r['date'] as String),
          ts: r['ts'] as String,
        )
    ];
  }

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
    _db.execute(
      'INSERT INTO habits '
      '(id, label, color, polarity, daily_target, created_at, archived) '
      'VALUES (?, ?, ?, ?, ?, ?, 0)',
      [
        habit.id,
        habit.label,
        habit.colorHex,
        habit.polarity.name,
        habit.dailyTarget,
        habit.createdAt,
      ],
    );
    return habit;
  }

  @override
  HabitEvent incrementHabit(String habitId, {CivilDate? date}) {
    final exists = _db.select('SELECT 1 FROM habits WHERE id = ?', [habitId]);
    if (exists.isEmpty) throw StateError('No habit "$habitId"');
    final now = _clock();
    final event = HabitEvent(
      id: _idFactory(),
      habitId: habitId,
      date: date ?? CivilDate.fromDateTime(now),
      ts: now.toUtc().toIso8601String(),
    );
    _db.execute(
      'INSERT INTO habit_events (id, habit_id, date, ts) VALUES (?, ?, ?, ?)',
      [event.id, event.habitId, event.date.iso, event.ts],
    );
    return event;
  }

  @override
  bool decrementHabit(String habitId, CivilDate date) {
    // Remove the most recent event for this habit/date (highest ts).
    final rows = _db.select(
      'SELECT id FROM habit_events WHERE habit_id = ? AND date = ? '
      'ORDER BY ts DESC, id DESC LIMIT 1',
      [habitId, date.iso],
    );
    if (rows.isEmpty) return false;
    _db.execute(
      'DELETE FROM habit_events WHERE id = ?',
      [rows.first['id'] as String],
    );
    return true;
  }

  static HabitPolarity _parsePolarity(String s) => HabitPolarity.values
      .firstWhere((v) => v.name == s, orElse: () => HabitPolarity.good);

  @override
  DaySnapshot snapshot() => DaySnapshot(
        profiles: profiles(),
        activeProfileId: _activeId,
        tasks: tasks(),
        completions: completions(),
        logs: logs(),
        habits: habits(),
        habitEvents: habitEvents(),
        subBlocks: _loadSubBlockMap(),
      );

  @override
  void restore(DaySnapshot snapshot) {
    _db.execute('BEGIN');
    try {
      for (final t in const [
        'segments',
        'sub_segments',
        'habit_events',
        'habits',
        'task_completions',
        'time_logs',
        'recurring_tasks',
        'profiles',
      ]) {
        _db.execute('DELETE FROM $t');
      }
      for (final p in snapshot.profiles) {
        _insertProfile(p);
      }
      _setSetting('active_profile_id', snapshot.activeProfileId);
      _writeSubBlocks(snapshot.subBlocks);
      for (final t in snapshot.tasks) {
        _db.execute(
          'INSERT INTO recurring_tasks '
          '(id, label, color, recurrence_rule, created_at, archived) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            t.id,
            t.label,
            t.colorHex,
            t.recurrence.encode(),
            t.createdAt,
            t.archived ? 1 : 0,
          ],
        );
      }
      for (final c in snapshot.completions) {
        _db.execute(
          'INSERT INTO task_completions (id, task_id, date, completed_at) '
          'VALUES (?, ?, ?, ?)',
          [c.id, c.taskId, c.date.iso, c.completedAt],
        );
      }
      for (final l in snapshot.logs) {
        _db.execute(
          'INSERT INTO time_logs '
          '(id, date, start_ts, end_ts, category, segment_id, note, source) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            l.id,
            l.date.iso,
            l.startTs,
            l.endTs,
            l.category,
            l.segmentId,
            l.note,
            l.source.name,
          ],
        );
      }
      for (final h in snapshot.habits) {
        _db.execute(
          'INSERT INTO habits '
          '(id, label, color, polarity, daily_target, created_at, archived) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            h.id,
            h.label,
            h.colorHex,
            h.polarity.name,
            h.dailyTarget,
            h.createdAt,
            h.archived ? 1 : 0,
          ],
        );
      }
      for (final e in snapshot.habitEvents) {
        _db.execute(
          'INSERT INTO habit_events (id, habit_id, date, ts) '
          'VALUES (?, ?, ?, ?)',
          [e.id, e.habitId, e.date.iso, e.ts],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
