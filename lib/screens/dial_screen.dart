import 'dart:async';
import 'dart:collection';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../agent/agent_host.dart';
import '../painters/dial_painter.dart';
import '../widgets/dial_view.dart';
import 'agent_screen.dart';
import 'stats_screen.dart';

/// The main dial screen: the dial plus its controls, a resize editor, and the
/// must-do tray. State is minimal `setState`; all reads/writes go through a
/// [DayRepository] (CLAUDE.md: the UI is wiring; logic + persistence live
/// behind the repository).
class DialScreen extends StatefulWidget {
  const DialScreen({
    super.key,
    required this.repository,
    required this.agentHost,
  });

  final DayRepository repository;
  final AgentHost agentHost;

  @override
  State<DialScreen> createState() => _DialScreenState();
}

class _DialScreenState extends State<DialScreen> {
  DayRepository get _repo => widget.repository;

  late DayProfile _profile;
  late SubBlockPlan _subBlocks;
  late List<RecurringTask> _tasks;
  late List<TaskCompletion> _completions;
  late List<Habit> _habits;
  late List<HabitEvent> _habitEvents;
  late List<TimeLog> _logs;

  DialMode _mode = DialMode.compass;
  bool _live = true;
  int _nowMin = _minuteOfNow();
  String? _selectedId;

  // In-progress tracking session (null when idle). Lives only in memory; a
  // completed session is written to the repository on stop.
  String? _trackStartTs;
  String? _trackCategory;
  String? _trackSegmentId;

  final CivilDate _today = CivilDate.fromDateTime(DateTime.now());
  Timer? _timer;

  bool get _tracking => _trackStartTs != null;

  static int _minuteOfNow() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  @override
  void initState() {
    super.initState();
    _loadFromRepo();
    _startClock();
  }

  void _loadFromRepo() {
    _profile = _repo.activeProfile();
    _subBlocks = _repo.subBlocks();
    _tasks = _repo.tasks();
    _completions = _repo.completions();
    _habits = _repo.habits();
    _habitEvents = _repo.habitEvents();
    _logs = _repo.logs();
  }

  void _startClock() {
    _timer?.cancel();
    // Tick every second while tracking (live elapsed), else once a minute-ish.
    final period = Duration(seconds: _tracking ? 1 : 10);
    if (!_live && !_tracking) return;
    _timer = Timer.periodic(period, (_) {
      if (mounted) setState(() => _nowMin = _minuteOfNow());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _indexOf(String id) => _profile.segments.indexWhere((s) => s.id == id);

  /// Resizes the selected wedge by moving its end boundary (persisted). A move
  /// that would breach the 15-min minimum or cross a neighbor is rejected by
  /// core and left as a no-op.
  void _resizeSelected(int delta) {
    final id = _selectedId;
    if (id == null) return;
    final seg = _profile.segments[_indexOf(id)];
    try {
      _repo.updateBlock(id, endMin: seg.endMin + delta);
    } on InvalidProfileException {
      return;
    }
    setState(() => _profile = _repo.activeProfile());
  }

  void _toggleTask(String taskId, bool currentlyDone) {
    if (currentlyDone) {
      _repo.uncompleteTask(taskId, _today);
    } else {
      _repo.completeTask(taskId, _today);
    }
    setState(() => _completions = _repo.completions());
  }

  void _bumpHabit(String habitId, int delta) {
    if (delta < 0) {
      _repo.decrementHabit(habitId, _today);
    } else {
      _repo.incrementHabit(habitId, date: _today);
    }
    setState(() => _habitEvents = _repo.habitEvents());
  }

  Future<void> _addHabitDialog() async {
    final result = await showDialog<_NewHabit>(
      context: context,
      builder: (_) => const _AddHabitDialog(),
    );
    if (result == null) return;
    _repo.addHabit(
      label: result.label,
      colorHex: result.polarity == HabitPolarity.bad ? '#B5624F' : '#6FA85B',
      polarity: result.polarity,
      dailyTarget: result.target,
    );
    setState(() {
      _habits = _repo.habits();
      _habitEvents = _repo.habitEvents();
    });
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addBlockDialog() async {
    final r = await showDialog<_BlockData>(
      context: context,
      builder: (_) => const _BlockDialog(title: 'Add block', geometry: true),
    );
    if (r == null) return;
    try {
      final seg = _repo.addBlock(
        name: r.name,
        colorHex: r.colorHex,
        startMin: r.startMin!,
        endMin: r.endMin!,
      );
      setState(() {
        _profile = _repo.activeProfile();
        _selectedId = seg.id;
      });
    } on InvalidProfileException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _editBlockDialog(Segment seg) async {
    final r = await showDialog<_BlockData>(
      context: context,
      builder: (_) => _BlockDialog(
        title: 'Edit block',
        geometry: false,
        initialName: seg.name,
        initialColor: seg.colorHex,
      ),
    );
    if (r == null) return;
    try {
      _repo.updateBlock(seg.id, name: r.name, colorHex: r.colorHex);
      setState(() => _profile = _repo.activeProfile());
    } on InvalidProfileException catch (e) {
      _showError(e.message);
    }
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    try {
      _repo.deleteBlock(id);
      setState(() {
        _profile = _repo.activeProfile();
        _selectedId = null;
        _subBlocks = _repo.subBlocks(); // deleting a parent drops its detail
      });
    } on InvalidProfileException catch (e) {
      _showError(e.message);
    }
  }

  // ---- sub-blocks (detail inside a block) ----

  Future<void> _addSubBlockDialog(Segment parent) async {
    final r = await showDialog<_BlockData>(
      context: context,
      builder: (_) => _BlockDialog(
        title: 'Add detail',
        geometry: true,
        initialColor: parent.colorHex,
        initialStartMin: parent.startMin,
        initialEndMin: normalizeMinute(parent.startMin + 60),
      ),
    );
    if (r == null) return;
    try {
      _repo.addSubBlock(
        parentId: parent.id,
        name: r.name,
        colorHex: r.colorHex,
        startMin: r.startMin!,
        endMin: r.endMin!,
      );
      setState(() => _subBlocks = _repo.subBlocks());
    } on InvalidSubBlockException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _editSubBlockDialog(Segment sub) async {
    final r = await showDialog<_BlockData>(
      context: context,
      builder: (_) => _BlockDialog(
        title: 'Edit detail',
        geometry: true,
        initialName: sub.name,
        initialColor: sub.colorHex,
        initialStartMin: sub.startMin,
        initialEndMin: sub.endMin,
      ),
    );
    if (r == null) return;
    try {
      _repo.updateSubBlock(
        sub.id,
        name: r.name,
        colorHex: r.colorHex,
        startMin: r.startMin,
        endMin: r.endMin,
      );
      setState(() => _subBlocks = _repo.subBlocks());
    } on InvalidSubBlockException catch (e) {
      _showError(e.message);
    }
  }

  void _deleteSubBlock(String id) {
    _repo.deleteSubBlock(id);
    setState(() => _subBlocks = _repo.subBlocks());
  }

  Future<void> _addTaskDialog() async {
    final r = await showDialog<_TaskData>(
      context: context,
      builder: (_) => const _TaskDialog(),
    );
    if (r == null) return;
    _repo.addRecurringTask(
      label: r.label,
      recurrence: r.recurrence,
      colorHex: r.colorHex,
    );
    setState(() => _tasks = _repo.tasks());
  }

  Future<void> _editTaskDialog(RecurringTask task) async {
    final r = await showDialog<_TaskData>(
      context: context,
      builder: (_) => _TaskDialog(initial: task),
    );
    if (r == null) return;
    _repo.updateRecurringTask(
      task.id,
      label: r.label,
      recurrence: r.recurrence,
      colorHex: r.colorHex,
    );
    setState(() => _tasks = _repo.tasks());
  }

  void _archiveTask(String id) {
    _repo.setTaskArchived(id, archived: true);
    setState(() => _tasks = _repo.tasks());
  }

  void _deleteTask(String id) {
    _repo.deleteRecurringTask(id);
    setState(() {
      _tasks = _repo.tasks();
      _completions = _repo.completions();
    });
  }

  // ---- tracking ----

  void _startTracking() {
    final seg = _profile.segmentAt(_minuteOfNow());
    setState(() {
      _trackStartTs = DateTime.now().toUtc().toIso8601String();
      _trackCategory = seg.name;
      _trackSegmentId = seg.id;
      _startClock();
    });
  }

  void _stopTracking() {
    final start = _trackStartTs;
    if (start == null) return;
    _repo.logActual(
      category: _trackCategory!,
      segmentId: _trackSegmentId,
      startTs: start,
      endTs: DateTime.now().toUtc().toIso8601String(),
    );
    setState(() {
      _trackStartTs = null;
      _trackCategory = null;
      _trackSegmentId = null;
      _logs = _repo.logs();
      _startClock();
    });
  }

  Duration get _elapsed => _trackStartTs == null
      ? Duration.zero
      : DateTime.now().difference(DateTime.parse(_trackStartTs!));

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  int _localMinuteOfDay(DateTime instant) {
    final l = instant.toLocal();
    return l.hour * 60 + l.minute;
  }

  String _colorForCategory(String category) {
    for (final s in _profile.segments) {
      if (s.name == category) return s.colorHex;
    }
    return '#F2E9D8';
  }

  /// Today's logged actuals as dial arcs, plus the in-progress session (if any).
  List<ActualArc> _actualArcs() {
    final arcs = <ActualArc>[
      for (final log in _logs)
        if (log.date == _today)
          ActualArc(
            startMin: _localMinuteOfDay(log.start),
            endMin: _localMinuteOfDay(log.end),
            colorHex: _colorForCategory(log.category),
          ),
    ];
    if (_tracking) {
      arcs.add(
        ActualArc(
          startMin: _localMinuteOfDay(DateTime.parse(_trackStartTs!)),
          endMin: _minuteOfNow(),
          colorHex: _colorForCategory(_trackCategory!),
        ),
      );
    }
    return arcs;
  }

  @override
  Widget build(BuildContext context) {
    final cur = _profile.segmentAt(_nowMin);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(cur),
                  const SizedBox(height: 16),
                  _dialCard(),
                  const SizedBox(height: 12),
                  _trackingCard(cur),
                  const SizedBox(height: 16),
                  _liveControls(),
                  const SizedBox(height: 12),
                  _selectedEditor(),
                  const SizedBox(height: 12),
                  _tray(),
                  const SizedBox(height: 12),
                  _habitsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openStats() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StatsScreen(repository: _repo)));
  }

  void _openAgent() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AgentScreen(host: widget.agentHost)),
    );
  }

  Widget _header(Segment cur) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR DAY · 24H',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              Text(
                formatMinuteOfDay(_nowMin),
                style: const TextStyle(
                  fontSize: 20,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Plan vs actual',
          onPressed: _openStats,
          icon: const Icon(Icons.insights),
        ),
        IconButton(
          tooltip: 'Agent',
          onPressed: _openAgent,
          icon: const Icon(Icons.smart_toy_outlined),
        ),
        const SizedBox(width: 4),
        SegmentedButton<DialMode>(
          segments: const [
            ButtonSegment(value: DialMode.compass, label: Text('Compass')),
            ButtonSegment(value: DialMode.clock, label: Text('Clock')),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
      ],
    );
  }

  Widget _dialCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1322),
        borderRadius: BorderRadius.circular(24),
      ),
      child: DialView(
        profile: _profile,
        nowMin: _nowMin,
        mode: _mode,
        selectedSegmentId: _selectedId,
        actuals: _actualArcs(),
        subBlocks: _subBlocks,
        onSegmentTapped: (id) => setState(() => _selectedId = id),
      ),
    );
  }

  Widget _trackingCard(Segment cur) {
    final tracking = _tracking;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1322),
        borderRadius: BorderRadius.circular(12),
        border: tracking
            ? Border.all(
                color: parseHexColor(_colorForCategory(_trackCategory!)),
              )
            : null,
      ),
      child: Row(
        children: [
          if (tracking) ...[
            Icon(
              Icons.fiber_manual_record,
              size: 12,
              color: parseHexColor(_colorForCategory(_trackCategory!)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: tracking
                ? Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Tracking ${_trackCategory!}',
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _mmss(_elapsed),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Track time for “${cur.name}”',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          if (tracking)
            FilledButton(onPressed: _stopTracking, child: const Text('Stop'))
          else
            FilledButton.tonalIcon(
              onPressed: _startTracking,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start'),
            ),
        ],
      ),
    );
  }

  Widget _liveControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => setState(() {
                  _live = !_live;
                  if (_live) _nowMin = _minuteOfNow();
                  _startClock();
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_live) ...[
                      const Icon(
                        Icons.circle,
                        size: 10,
                        color: Color(0xFF6FA85B),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Text('Live'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Scrub'),
            Expanded(
              child: Slider(
                value: _nowMin.toDouble(),
                max: 1439,
                onChanged: (v) => setState(() {
                  _live = false;
                  _timer?.cancel();
                  _nowMin = v.round();
                }),
              ),
            ),
            Text(
              formatMinuteOfDay(_nowMin),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _selectedEditor() {
    final id = _selectedId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1322),
        borderRadius: BorderRadius.circular(12),
      ),
      child: id == null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Tap a wedge to edit it',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addBlockDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add block'),
                ),
              ],
            )
          : Builder(
              builder: (_) {
                final seg = _profile.segments[_indexOf(id)];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                seg.name,
                                style: TextStyle(
                                  color: parseHexColor(seg.colorHex),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${formatMinuteOfDay(seg.startMin)}–'
                                '${formatMinuteOfDay(seg.endMin)} · '
                                '${formatDuration(seg.durationMin)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Shorten',
                          onPressed: () => _resizeSelected(-15),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Lengthen',
                          onPressed: () => _resizeSelected(15),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Rename / recolor',
                          onPressed: () => _editBlockDialog(seg),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          color: const Color(0xFFB5624F),
                        ),
                      ],
                    ),
                    _subBlockSection(seg),
                  ],
                );
              },
            ),
    );
  }

  /// The "detail inside" editor for the selected block: its sub-blocks plus an
  /// add affordance. Reveals live on the dial as the block subdivides in place.
  Widget _subBlockSection(Segment parent) {
    final subs = _subBlocks.of(parent.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DETAIL INSIDE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            TextButton.icon(
              onPressed: () => _addSubBlockDialog(parent),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add detail'),
            ),
          ],
        ),
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'No detail yet — split this block into tasks',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ),
        for (final sub in subs) _subBlockRow(sub),
      ],
    );
  }

  Widget _subBlockRow(Segment sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: parseHexColor(sub.colorHex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(sub.name, overflow: TextOverflow.ellipsis)),
          Text(
            '${formatMinuteOfDay(sub.startMin)}–${formatMinuteOfDay(sub.endMin)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Edit detail',
            onPressed: () => _editSubBlockDialog(sub),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete detail',
            onPressed: () => _deleteSubBlock(sub.id),
            icon: const Icon(Icons.delete_outline, size: 18),
            color: const Color(0xFFB5624F),
          ),
        ],
      ),
    );
  }

  Widget _habitsSection() {
    final counts = habitCountsFor(_today, _habits, _habitEvents);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1322),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HABITS · TAP TO COUNT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              InkWell(
                key: const Key('add-habit'),
                onTap: _addHabitDialog,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (counts.isEmpty)
            Text(
              'No habits yet — add one with +',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          for (final c in counts) _habitRow(c),
        ],
      ),
    );
  }

  Widget _habitRow(HabitDayCount c) {
    final color = parseHexColor(c.habit.colorHex);
    final bad = c.habit.polarity == HabitPolarity.bad;
    final countText = c.target != null
        ? '${c.count} / ${c.target}'
        : '${c.count}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(c.habit.label)),
          Text(
            countText,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: c.targetReached
                  ? (bad ? const Color(0xFFB5624F) : const Color(0xFF6FA85B))
                  : Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: c.count > 0 ? () => _bumpHabit(c.habit.id, -1) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _bumpHabit(c.habit.id, 1),
            icon: Icon(Icons.add_circle, size: 22, color: color),
          ),
        ],
      ),
    );
  }

  Widget _tray() {
    final tray = trayFor(_today, _tasks, _completions);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1322),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MUST-DO TODAY · NO FIXED TIME',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              InkWell(
                key: const Key('add-task'),
                onTap: _addTaskDialog,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tray.isEmpty)
            Text(
              'Nothing due today',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          for (final item in tray)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _toggleTask(item.task.id, item.doneToday),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            item.doneToday
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 20,
                            color: parseHexColor(item.task.colorHex),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.task.label,
                              style: TextStyle(
                                decoration: item.doneToday
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: item.doneToday
                                    ? Colors.white.withValues(alpha: 0.4)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Task actions',
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _editTaskDialog(item.task);
                      case 'archive':
                        _archiveTask(item.task.id);
                      case 'delete':
                        _deleteTask(item.task.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit…')),
                    PopupMenuItem(value: 'archive', child: Text('Archive')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The result of the add-habit dialog.
class _NewHabit {
  const _NewHabit(this.label, this.polarity, this.target);
  final String label;
  final HabitPolarity polarity;
  final int? target;
}

/// A small dialog to create a habit: a name, good/bad, and an optional target.
class _AddHabitDialog extends StatefulWidget {
  const _AddHabitDialog();

  @override
  State<_AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends State<_AddHabitDialog> {
  final _label = TextEditingController();
  final _target = TextEditingController();
  HabitPolarity _polarity = HabitPolarity.good;

  @override
  void dispose() {
    _label.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New habit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<HabitPolarity>(
            segments: const [
              ButtonSegment(value: HabitPolarity.good, label: Text('Build up')),
              ButtonSegment(value: HabitPolarity.bad, label: Text('Cut down')),
            ],
            selected: {_polarity},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _polarity = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daily target (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            Navigator.pop(
              context,
              _NewHabit(label, _polarity, int.tryParse(_target.text.trim())),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// The block palette (prototype colors).
const List<String> _kPalette = [
  '#4B4FA6',
  '#C98A3E',
  '#2E8B8B',
  '#B5624F',
  '#3E7CB1',
  '#6FA85B',
  '#8E6FB0',
  '#5A9FB0',
];

/// A row of tappable color swatches.
class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in _kPalette)
          GestureDetector(
            onTap: () => onChanged(hex),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: parseHexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex == selected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Result of the block dialog.
class _BlockData {
  const _BlockData(this.name, this.startMin, this.endMin, this.colorHex);
  final String name;
  final int? startMin;
  final int? endMin;
  final String colorHex;
}

/// Add/edit a block. When [geometry] is true it collects start/end times too.
class _BlockDialog extends StatefulWidget {
  const _BlockDialog({
    required this.title,
    required this.geometry,
    this.initialName,
    this.initialColor,
    this.initialStartMin,
    this.initialEndMin,
  });

  final String title;
  final bool geometry;
  final String? initialName;
  final String? initialColor;
  final int? initialStartMin;
  final int? initialEndMin;

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _start = TextEditingController(
    text: widget.initialStartMin != null
        ? formatMinuteOfDay(widget.initialStartMin!)
        : '09:00',
  );
  late final _end = TextEditingController(
    text: widget.initialEndMin != null
        ? formatMinuteOfDay(widget.initialEndMin!)
        : '10:00',
  );
  late String _color = widget.initialColor ?? _kPalette.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    int? startMin;
    int? endMin;
    if (widget.geometry) {
      try {
        startMin = parseMinuteOfDay(_start.text);
        endMin = parseMinuteOfDay(_end.text);
      } on FormatException {
        setState(() => _error = 'Times must be HH:MM');
        return;
      }
    }
    Navigator.pop(context, _BlockData(name, startMin, endMin, _color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          if (widget.geometry) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    decoration: const InputDecoration(
                      labelText: 'Start (HH:MM)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _end,
                    decoration: const InputDecoration(labelText: 'End (HH:MM)'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _ColorSwatches(
            selected: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFB5624F))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Result of the task dialog.
class _TaskData {
  const _TaskData(this.label, this.recurrence, this.colorHex);
  final String label;
  final Recurrence recurrence;
  final String colorHex;
}

/// The recurrence shapes the dialog can build (SPEC §3). Mirrors the [Recurrence]
/// subtypes in core.
enum _RecKind { daily, weekly, interval, dates }

/// Add or edit a recurring task: a label, a recurrence rule (every day, certain
/// weekdays, every N days, or specific dates), and a color. Pass [initial] to
/// edit an existing task; omit it to create a new one.
class _TaskDialog extends StatefulWidget {
  const _TaskDialog({this.initial});

  final RecurringTask? initial;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _label;
  late final TextEditingController _interval;
  late _RecKind _kind;
  final Set<int> _days = {}; // ISO weekdays 1..7 (weekly)
  final SplayTreeSet<CivilDate> _dates = SplayTreeSet(); // specific dates
  late CivilDate _anchor; // interval anchor (kept when editing)
  late String _color;
  String? _error;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final task = widget.initial;
    _label = TextEditingController(text: task?.label ?? '');
    _color = task?.colorHex ?? _kPalette[4];
    _anchor = CivilDate.fromDateTime(DateTime.now());
    var intervalN = 2;

    switch (task?.recurrence) {
      case WeeklyRecurrence(:final weekdays):
        _kind = _RecKind.weekly;
        _days.addAll(weekdays);
      case IntervalRecurrence(:final intervalDays, :final anchor):
        _kind = _RecKind.interval;
        intervalN = intervalDays;
        _anchor = anchor;
      case DatesRecurrence(:final dates):
        _kind = _RecKind.dates;
        _dates.addAll(dates);
      case _:
        _kind = _RecKind.daily;
    }
    _interval = TextEditingController(text: '$intervalN');
  }

  @override
  void dispose() {
    _label.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _addDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _dates.add(CivilDate.fromDateTime(picked)));
    }
  }

  /// Builds the recurrence from the current inputs, or sets [_error] and returns
  /// null if the inputs are incomplete.
  Recurrence? _buildRecurrence() {
    switch (_kind) {
      case _RecKind.daily:
        return const DailyRecurrence();
      case _RecKind.weekly:
        if (_days.isEmpty) {
          _error = 'Pick at least one weekday';
          return null;
        }
        return WeeklyRecurrence(_days);
      case _RecKind.interval:
        final n = int.tryParse(_interval.text.trim());
        if (n == null || n < 1) {
          _error = 'Interval must be a whole number of days ≥ 1';
          return null;
        }
        return IntervalRecurrence(n, _anchor);
      case _RecKind.dates:
        if (_dates.isEmpty) {
          _error = 'Add at least one date';
          return null;
        }
        return DatesRecurrence(_dates.toSet());
    }
  }

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final recurrence = _buildRecurrence();
    if (recurrence == null) {
      setState(() {}); // surface _error set by _buildRecurrence
      return;
    }
    Navigator.pop(context, _TaskData(label, recurrence, _color));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit task' : 'New task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_RecKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: const [
                DropdownMenuItem(
                  value: _RecKind.daily,
                  child: Text('Every day'),
                ),
                DropdownMenuItem(
                  value: _RecKind.weekly,
                  child: Text('Certain weekdays'),
                ),
                DropdownMenuItem(
                  value: _RecKind.interval,
                  child: Text('Every N days'),
                ),
                DropdownMenuItem(
                  value: _RecKind.dates,
                  child: Text('Specific dates'),
                ),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _RecKind.daily),
            ),
            if (_kind == _RecKind.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_dayLabels[d - 1]),
                      selected: _days.contains(d),
                      onSelected: (on) =>
                          setState(() => on ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
            ],
            if (_kind == _RecKind.interval) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Every'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('days'),
                ],
              ),
            ],
            if (_kind == _RecKind.dates) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in _dates)
                    InputChip(
                      label: Text(d.iso),
                      onDeleted: () => setState(() => _dates.remove(d)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add date'),
                    onPressed: _addDate,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _ColorSwatches(
              selected: _color,
              onChanged: (c) => setState(() => _color = c),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB5624F))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }
}
