import 'package:day_dial_core/day_dial_core.dart';

import 'consent.dart';
import 'repository.dart';

/// Metadata for one MCP tool: its name, one-line description, and whether it
/// mutates state / is destructive (mirrors MCP's `destructiveHint`).
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    this.mutates = false,
    this.destructive = false,
  });

  final String name;
  final String description;
  final bool mutates;
  final bool destructive;
}

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
  static const List<ToolSpec> specs = [
    ToolSpec(name: 'get_current_block', description: 'The block active now.'),
    ToolSpec(name: 'get_day', description: 'A day\'s blocks and task tray.'),
    ToolSpec(name: 'list_upcoming', description: 'The next N upcoming blocks.'),
    ToolSpec(
        name: 'get_recurring_tasks',
        description: 'Untimed recurring tasks and today\'s done state.'),
    ToolSpec(
        name: 'get_stats',
        description: 'Plan-vs-actual variance over a range.'),
    ToolSpec(
        name: 'add_block',
        description: 'Add a block to the active profile.',
        mutates: true),
    ToolSpec(
        name: 'update_block',
        description: 'Move, resize, rename, or recolor a block.',
        mutates: true),
    ToolSpec(
        name: 'delete_block',
        description: 'Delete a block; its span merges into a neighbor.',
        mutates: true,
        destructive: true),
    ToolSpec(
        name: 'add_recurring_task',
        description: 'Add an untimed recurring task.',
        mutates: true),
    ToolSpec(
        name: 'complete_task',
        description: 'Mark a recurring task done on a date.',
        mutates: true),
    ToolSpec(
        name: 'switch_profile',
        description: 'Make a profile the active day layout.',
        mutates: true),
    ToolSpec(
        name: 'log_actual',
        description: 'Record what actually happened (append-only).',
        mutates: true),
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
      case 'switch_profile':
        return _switchProfile(args);
      case 'log_actual':
        return _logActual(args);
      default:
        throw ArgumentError('Unhandled tool "$tool"');
    }
  }

  // ---- reads ----------------------------------------------------------------

  Map<String, Object?> _getCurrentBlock(Map<String, Object?> args) {
    final now = _nowMin(args['now']);
    final profile = repo.activeProfile();
    final seg = profile.segmentAt(now);
    return {
      'name': seg.name,
      'color': seg.colorHex,
      'startsAt': formatMinuteOfDay(seg.startMin),
      'endsAt': formatMinuteOfDay(seg.endMin),
      'minutesRemaining': profile.remainingAt(now),
      'profile': profile.name,
    };
  }

  Map<String, Object?> _getDay(Map<String, Object?> args) {
    final date = _date(args['date']);
    final profile = repo.activeProfile();
    return {
      'date': date.iso,
      'profile': profile.name,
      'blocks': [for (final s in profile.segments) _block(s)],
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
