import 'package:day_dial_core/day_dial_core.dart';

import 'consent.dart';

/// Metadata for one MCP tool: its name, one-line description, and whether it
/// mutates state / is destructive (mirrors MCP's `destructiveHint`).
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    this.inputSchema = _emptyObjectSchema,
    this.mutates = false,
    this.destructive = false,
  });

  final String name;
  final String description;

  /// JSON Schema for the tool's arguments, surfaced via MCP `tools/list`.
  final Map<String, Object?> inputSchema;
  final bool mutates;
  final bool destructive;

  static const Map<String, Object?> _emptyObjectSchema = {
    'type': 'object',
    'properties': <String, Object?>{},
  };
}

/// Builds an object JSON Schema. Kept terse — MCP clients only need enough to
/// prompt/validate arguments.
Map<String, Object?> _schema(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) =>
    {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };

const _timeArg = {
  'type': 'string',
  'description': 'Time as "HH:MM" or minutes-since-midnight',
};
const _dateArg = {'type': 'string', 'description': 'Date as YYYY-MM-DD'};
const _colorArg = {'type': 'string', 'description': 'Hex color, e.g. #3E7CB1'};

/// Dispatches Day-Dial's MCP tool calls (SPEC §6.2) against a [DayRepository],
/// routing every mutating tool through a [ConsentGate] first. Read tools run
/// directly. Results are JSON-ready maps/lists.
///
/// This is transport-agnostic: a stdio or Streamable HTTP server wraps [call]
/// and [specs]; it is not itself a server.
class DayDialTools {
  DayDialTools(
    this.repo,
    this.consent, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DayRepository repo;
  final ConsentGate consent;
  final DateTime Function() _clock;

  /// The full tool catalog, for MCP `tools/list`.
  static final List<ToolSpec> specs = [
    ToolSpec(
      name: 'get_current_block',
      description: 'The block active now.',
      inputSchema: _schema({'now': _timeArg}),
    ),
    ToolSpec(
      name: 'get_day',
      description: 'A day\'s blocks and task tray.',
      inputSchema: _schema({'date': _dateArg}),
    ),
    ToolSpec(
      name: 'list_upcoming',
      description: 'The next N upcoming blocks.',
      inputSchema: _schema({
        'count': {'type': 'integer', 'description': 'How many (default 3)'},
        'from': _timeArg,
      }),
    ),
    ToolSpec(
      name: 'get_recurring_tasks',
      description: 'Untimed recurring tasks and today\'s done state.',
      inputSchema: _schema({
        'status': {
          'type': 'string',
          'enum': ['all', 'done', 'pending'],
        },
        'date': _dateArg,
      }),
    ),
    ToolSpec(
      name: 'get_stats',
      description: 'Plan-vs-actual variance over a range.',
      inputSchema: _schema({
        'range': {
          'type': 'string',
          'enum': ['day', 'week', 'month'],
        },
        'metric': {'type': 'string'},
      }),
    ),
    ToolSpec(
      name: 'add_block',
      description: 'Add a block to the active profile.',
      inputSchema: _schema({
        'name': {'type': 'string'},
        'start': _timeArg,
        'end': _timeArg,
        'color': _colorArg,
      }, required: [
        'name',
        'start',
        'end'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'update_block',
      description: 'Move, resize, rename, or recolor a block.',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'name': {'type': 'string'},
        'start': _timeArg,
        'end': _timeArg,
        'color': _colorArg,
      }, required: [
        'id'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'delete_block',
      description: 'Delete a block; its span merges into a neighbor.',
      inputSchema: _schema({
        'id': {'type': 'string'},
      }, required: [
        'id'
      ]),
      mutates: true,
      destructive: true,
    ),
    ToolSpec(
      name: 'add_recurring_task',
      description: 'Add an untimed recurring task.',
      inputSchema: _schema({
        'label': {'type': 'string'},
        'recurrence': {
          'type': 'string',
          'description':
              'daily | weekly:1,3,5 | interval:N@YYYY-MM-DD | dates:YYYY-MM-DD,...',
        },
        'color': _colorArg,
      }, required: [
        'label',
        'recurrence'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'complete_task',
      description: 'Mark a recurring task done on a date.',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'date': _dateArg,
      }, required: [
        'id'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'switch_profile',
      description: 'Make a profile the active day layout.',
      inputSchema: _schema({
        'profile': {'type': 'string'},
      }, required: [
        'profile'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'log_actual',
      description: 'Record what actually happened (append-only).',
      inputSchema: _schema({
        'category': {'type': 'string'},
        'blockId': {'type': 'string'},
        'start': {'type': 'string', 'description': 'ISO-8601 timestamp'},
        'end': {'type': 'string', 'description': 'ISO-8601 timestamp'},
        'note': {'type': 'string'},
      }, required: [
        'start',
        'end'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'get_habits',
      description: 'Countable habits with today\'s (or a date\'s) tally.',
      inputSchema: _schema({'date': _dateArg}),
    ),
    ToolSpec(
      name: 'add_habit',
      description: 'Create a countable habit (e.g. water, cigarettes).',
      inputSchema: _schema({
        'label': {'type': 'string'},
        'polarity': {
          'type': 'string',
          'enum': ['good', 'bad'],
          'description': 'good = build up, bad = cut down',
        },
        'target': {'type': 'integer', 'description': 'Optional daily goal/cap'},
        'color': _colorArg,
      }, required: [
        'label'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'log_habit',
      description: 'Increment (or decrement) a habit\'s tally for a date.',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'date': _dateArg,
        'delta': {
          'type': 'integer',
          'description': '+1 (default) adds an occurrence, -1 removes one',
        },
      }, required: [
        'id'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'update_recurring_task',
      description: 'Edit a recurring task\'s label, recurrence, or color.',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'label': {'type': 'string'},
        'recurrence': {
          'type': 'string',
          'description':
              'daily | weekly:1,3,5 | interval:N@YYYY-MM-DD | dates:YYYY-MM-DD,...',
        },
        'color': _colorArg,
      }, required: [
        'id'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'set_task_archived',
      description: 'Archive or un-archive a recurring task (hides it from the '
          'tray, keeps its history).',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'archived': {'type': 'boolean'},
      }, required: [
        'id',
        'archived'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'delete_recurring_task',
      description: 'Permanently delete a recurring task and its completions.',
      inputSchema: _schema({
        'id': {'type': 'string'},
      }, required: [
        'id'
      ]),
      mutates: true,
      destructive: true,
    ),
    ToolSpec(
      name: 'get_sub_blocks',
      description:
          'The sub-blocks planned inside blocks (optionally one block).',
      inputSchema: _schema({
        'parentId': {'type': 'string', 'description': 'Limit to one block'},
      }),
    ),
    ToolSpec(
      name: 'add_sub_block',
      description:
          'Add a detail sub-block inside a block (must fit within it).',
      inputSchema: _schema({
        'parentId': {'type': 'string'},
        'name': {'type': 'string'},
        'start': _timeArg,
        'end': _timeArg,
        'color': _colorArg,
      }, required: [
        'parentId',
        'name',
        'start',
        'end'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'update_sub_block',
      description: 'Move, resize, rename, or recolor a detail sub-block.',
      inputSchema: _schema({
        'id': {'type': 'string'},
        'name': {'type': 'string'},
        'start': _timeArg,
        'end': _timeArg,
        'color': _colorArg,
      }, required: [
        'id'
      ]),
      mutates: true,
    ),
    ToolSpec(
      name: 'delete_sub_block',
      description: 'Delete a detail sub-block.',
      inputSchema: _schema({
        'id': {'type': 'string'},
      }, required: [
        'id'
      ]),
      mutates: true,
      destructive: true,
    ),
  ];

  static ToolSpec _spec(String name) => specs.firstWhere(
        (s) => s.name == name,
        orElse: () => throw ArgumentError('Unknown tool "$name"'),
      );

  /// Invokes [tool] with [args], returning a JSON-ready result. Mutating tools
  /// require consent; a denied gate throws [ConsentDeniedException] and nothing
  /// is changed.
  Future<Object?> call(String tool,
      [Map<String, Object?> args = const {}]) async {
    final spec = _spec(tool);
    if (spec.mutates) {
      final granted = await consent.requestConsent(ToolCall(
        tool: tool,
        arguments: args,
        destructive: spec.destructive,
      ));
      if (!granted) throw ConsentDeniedException(tool);
    }

    switch (tool) {
      case 'get_current_block':
        return _getCurrentBlock(args);
      case 'get_day':
        return _getDay(args);
      case 'list_upcoming':
        return _listUpcoming(args);
      case 'get_recurring_tasks':
        return _getRecurringTasks(args);
      case 'get_stats':
        return _getStats(args);
      case 'add_block':
        return _addBlock(args);
      case 'update_block':
        return _updateBlock(args);
      case 'delete_block':
        return _deleteBlock(args);
      case 'add_recurring_task':
        return _addRecurringTask(args);
      case 'complete_task':
        return _completeTask(args);
      case 'update_recurring_task':
        return _updateRecurringTask(args);
      case 'set_task_archived':
        return _setTaskArchived(args);
      case 'delete_recurring_task':
        return _deleteRecurringTask(args);
      case 'get_sub_blocks':
        return _getSubBlocks(args);
      case 'add_sub_block':
        return _addSubBlock(args);
      case 'update_sub_block':
        return _updateSubBlock(args);
      case 'delete_sub_block':
        return _deleteSubBlock(args);
      case 'switch_profile':
        return _switchProfile(args);
      case 'log_actual':
        return _logActual(args);
      case 'get_habits':
        return _getHabits(args);
      case 'add_habit':
        return _addHabit(args);
      case 'log_habit':
        return _logHabit(args);
      default:
        throw ArgumentError('Unhandled tool "$tool"');
    }
  }

  // ---- reads ----------------------------------------------------------------

  Map<String, Object?> _getCurrentBlock(Map<String, Object?> args) {
    final now = _nowMin(args['now']);
    final profile = repo.activeProfile();
    final seg = profile.segmentAt(now);
    final detail = activeSubBlockAt(seg, repo.subBlocks().of(seg.id), now);
    return {
      'name': seg.name,
      'color': seg.colorHex,
      'startsAt': formatMinuteOfDay(seg.startMin),
      'endsAt': formatMinuteOfDay(seg.endMin),
      'minutesRemaining': profile.remainingAt(now),
      'profile': profile.name,
      // The finer sub-block you're inside right now, if any (else null).
      'activeDetail': detail == null
          ? null
          : {
              'name': detail.name,
              'color': detail.colorHex,
              'startsAt': formatMinuteOfDay(detail.startMin),
              'endsAt': formatMinuteOfDay(detail.endMin),
              'minutesRemaining': spanMinutes(now, detail.endMin),
            },
    };
  }

  Map<String, Object?> _getDay(Map<String, Object?> args) {
    final date = _date(args['date']);
    final profile = repo.activeProfile();
    final plan = repo.subBlocks();
    return {
      'date': date.iso,
      'profile': profile.name,
      'blocks': [
        for (final s in profile.segments)
          {
            ..._block(s),
            'detail': [for (final sub in plan.of(s.id)) _block(sub)],
          },
      ],
      'tasks': _trayJson(date),
    };
  }

  List<Map<String, Object?>> _listUpcoming(Map<String, Object?> args) {
    final count = (args['count'] as num?)?.toInt() ?? 3;
    final from = _nowMin(args['from']);
    return [
      for (final u in repo.activeProfile().upcomingFrom(from, count))
        {
          'name': u.segment.name,
          'start': formatMinuteOfDay(u.segment.startMin),
          'end': formatMinuteOfDay(u.segment.endMin),
          'inMinutes': u.inMinutes,
        }
    ];
  }

  List<Map<String, Object?>> _getRecurringTasks(Map<String, Object?> args) {
    final date = _date(args['date']);
    final status = (args['status'] as String?) ?? 'all';
    return _trayJson(date).where((t) {
      switch (status) {
        case 'done':
          return t['doneToday'] == true;
        case 'pending':
          return t['doneToday'] == false;
        default:
          return true;
      }
    }).toList();
  }

  Map<String, Object?> _getStats(Map<String, Object?> args) {
    final range = (args['range'] as String?) ?? 'week';
    final today = CivilDate.fromDateTime(_clock());
    final span = switch (range) {
      'day' => 0,
      'month' => 29,
      _ => 6, // week
    };
    final dates = today.addDays(-span).rangeTo(today);
    final variance = planVsActual(
      dates: dates,
      profileForDate: (_) => repo.activeProfile(),
      logs: repo.logs(),
    );
    return {
      'range': range,
      'perCategory': [
        for (final v in variance)
          {
            'category': v.category,
            'plannedMin': v.plannedMin,
            'actualMin': v.actualMin,
            'deltaMin': v.deltaMin,
          }
      ],
    };
  }

  // ---- writes ---------------------------------------------------------------

  Map<String, Object?> _addBlock(Map<String, Object?> args) {
    final seg = repo.addBlock(
      name: args['name']! as String,
      colorHex: (args['color'] as String?) ?? '#3E7CB1',
      startMin: _minute(args['start']),
      endMin: _minute(args['end']),
    );
    return _block(seg);
  }

  Map<String, Object?> _updateBlock(Map<String, Object?> args) {
    final seg = repo.updateBlock(
      args['id']! as String,
      name: args['name'] as String?,
      colorHex: args['color'] as String?,
      startMin: args.containsKey('start') ? _minute(args['start']) : null,
      endMin: args.containsKey('end') ? _minute(args['end']) : null,
    );
    return _block(seg);
  }

  Map<String, Object?> _deleteBlock(Map<String, Object?> args) {
    repo.deleteBlock(args['id']! as String);
    return {'ok': true};
  }

  Map<String, Object?> _addRecurringTask(Map<String, Object?> args) {
    final task = repo.addRecurringTask(
      label: args['label']! as String,
      recurrence: Recurrence.parse(args['recurrence']! as String),
      colorHex: (args['color'] as String?) ?? '#6FA85B',
    );
    return {
      'id': task.id,
      'label': task.label,
      'recurrence': task.recurrence.encode(),
      'color': task.colorHex,
    };
  }

  Map<String, Object?> _completeTask(Map<String, Object?> args) {
    repo.completeTask(args['id']! as String, _date(args['date']));
    return {'ok': true};
  }

  Map<String, Object?> _updateRecurringTask(Map<String, Object?> args) {
    final task = repo.updateRecurringTask(
      args['id']! as String,
      label: args['label'] as String?,
      colorHex: args['color'] as String?,
      recurrence: args.containsKey('recurrence')
          ? Recurrence.parse(args['recurrence']! as String)
          : null,
    );
    return {
      'id': task.id,
      'label': task.label,
      'recurrence': task.recurrence.encode(),
      'color': task.colorHex,
      'archived': task.archived,
    };
  }

  Map<String, Object?> _setTaskArchived(Map<String, Object?> args) {
    repo.setTaskArchived(
      args['id']! as String,
      archived: args['archived']! as bool,
    );
    return {'ok': true};
  }

  Map<String, Object?> _deleteRecurringTask(Map<String, Object?> args) {
    repo.deleteRecurringTask(args['id']! as String);
    return {'ok': true};
  }

  List<Map<String, Object?>> _getSubBlocks(Map<String, Object?> args) {
    final plan = repo.subBlocks();
    final only = args['parentId'] as String?;
    final parents = only != null ? [only] : plan.parentIds.toList();
    return [
      for (final pid in parents)
        for (final s in plan.of(pid)) {'parentId': pid, ..._block(s)},
    ];
  }

  Map<String, Object?> _addSubBlock(Map<String, Object?> args) {
    final parentId = args['parentId']! as String;
    final seg = repo.addSubBlock(
      parentId: parentId,
      name: args['name']! as String,
      colorHex: (args['color'] as String?) ?? '#5A9FB0',
      startMin: _minute(args['start']),
      endMin: _minute(args['end']),
    );
    return {'parentId': parentId, ..._block(seg)};
  }

  Map<String, Object?> _updateSubBlock(Map<String, Object?> args) {
    final seg = repo.updateSubBlock(
      args['id']! as String,
      name: args['name'] as String?,
      colorHex: args['color'] as String?,
      startMin: args.containsKey('start') ? _minute(args['start']) : null,
      endMin: args.containsKey('end') ? _minute(args['end']) : null,
    );
    return _block(seg);
  }

  Map<String, Object?> _deleteSubBlock(Map<String, Object?> args) {
    repo.deleteSubBlock(args['id']! as String);
    return {'ok': true};
  }

  Map<String, Object?> _switchProfile(Map<String, Object?> args) {
    repo.switchProfile(args['profile']! as String);
    return {'ok': true};
  }

  Map<String, Object?> _logActual(Map<String, Object?> args) {
    // Either an explicit category or a blockId whose name becomes the category.
    String category;
    String? segmentId;
    final blockId = args['blockId'] as String?;
    if (blockId != null) {
      final seg = repo.activeProfile().segments.firstWhere(
            (s) => s.id == blockId,
            orElse: () => throw ArgumentError('No block "$blockId"'),
          );
      category = seg.name;
      segmentId = seg.id;
    } else {
      category = args['category']! as String;
    }
    final log = repo.logActual(
      category: category,
      segmentId: segmentId,
      startTs: args['start']! as String,
      endTs: args['end']! as String,
      note: args['note'] as String?,
      source: LogSource.agent,
    );
    return {
      'id': log.id,
      'category': log.category,
      'start': log.startTs,
      'end': log.endTs,
      'minutes': log.durationMin,
    };
  }

  List<Map<String, Object?>> _getHabits(Map<String, Object?> args) {
    final date = _date(args['date']);
    return [
      for (final h in habitCountsFor(date, repo.habits(), repo.habitEvents()))
        {
          'id': h.habit.id,
          'label': h.habit.label,
          'polarity': h.habit.polarity.name,
          'count': h.count,
          'target': h.target,
          'targetReached': h.targetReached,
        }
    ];
  }

  Map<String, Object?> _addHabit(Map<String, Object?> args) {
    final polarity = switch (args['polarity']) {
      'bad' => HabitPolarity.bad,
      _ => HabitPolarity.good,
    };
    final habit = repo.addHabit(
      label: args['label']! as String,
      colorHex: (args['color'] as String?) ?? '#6FA85B',
      polarity: polarity,
      dailyTarget: (args['target'] as num?)?.toInt(),
    );
    return {
      'id': habit.id,
      'label': habit.label,
      'polarity': habit.polarity.name,
      'target': habit.dailyTarget,
    };
  }

  Map<String, Object?> _logHabit(Map<String, Object?> args) {
    final id = args['id']! as String;
    final date = _date(args['date']);
    final delta = (args['delta'] as num?)?.toInt() ?? 1;
    if (delta < 0) {
      repo.decrementHabit(id, date);
    } else {
      repo.incrementHabit(id, date: date);
    }
    return {
      'id': id,
      'count': habitCountOn(date, id, repo.habitEvents()),
    };
  }

  // ---- helpers --------------------------------------------------------------

  Map<String, Object?> _block(Segment s) => {
        'id': s.id,
        'name': s.name,
        'color': s.colorHex,
        'start': formatMinuteOfDay(s.startMin),
        'end': formatMinuteOfDay(s.endMin),
      };

  List<Map<String, Object?>> _trayJson(CivilDate date) {
    final tray = trayFor(date, repo.tasks(), repo.completions());
    return [
      for (final item in tray)
        {
          'id': item.task.id,
          'label': item.task.label,
          'recurrence': item.task.recurrence.encode(),
          'doneToday': item.doneToday,
        }
    ];
  }

  /// Minutes-since-midnight for "now"-style args: an `int`/`num`, an `HH:MM`
  /// string, or (when absent) derived from the clock.
  int _nowMin(Object? v) {
    if (v == null) {
      final dt = _clock();
      return dt.hour * 60 + dt.minute;
    }
    return _minute(v);
  }

  int _minute(Object? v) {
    if (v is int) return normalizeMinute(v);
    if (v is num) return normalizeMinute(v.toInt());
    if (v is String) return parseMinuteOfDay(v);
    throw FormatException('Expected minute int or "HH:MM"', '$v');
  }

  CivilDate _date(Object? v) {
    if (v == null) return CivilDate.fromDateTime(_clock());
    if (v is String) return CivilDate.parse(v);
    throw FormatException('Expected YYYY-MM-DD date', '$v');
  }
}
