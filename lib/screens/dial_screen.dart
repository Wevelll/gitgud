import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../agent/agent_host.dart';
import '../calendar/calendar_service.dart';
import '../painters/dial_geometry.dart';
import '../painters/dial_painter.dart';
import '../widgets/dial_view.dart';
import 'agent_screen.dart';
import 'calendar_settings_screen.dart';
import 'focus_screen.dart';
import 'review_screen.dart';
import 'stats_screen.dart';
import 'templates_screen.dart';

/// The All-Dial shell (SPEC §2, design exploration D): the dial *is* the
/// interface. The hub is the tracking control, a tapped wedge opens a radial
/// popover editor, must-do tokens and habits float around the ring, and the
/// four corners are the entire navigation surface. All reads/writes go through a
/// [DayRepository] (CLAUDE.md: the UI is wiring; logic + persistence live behind
/// the repository).
class DialScreen extends StatefulWidget {
  const DialScreen({
    super.key,
    required this.repository,
    required this.agentHost,
    this.calendarService,
    this.onDayChanged,
  });

  final DayRepository repository;
  final AgentHost agentHost;

  /// Optional read-only calendar overlay (SPEC §12.1). Null keeps the dial
  /// calendar-free (local-first default).
  final CalendarService? calendarService;

  /// Called after an edit that changes the day's block boundaries, so the host
  /// can reschedule transition notifications. Optional (tests omit it).
  final VoidCallback? onDayChanged;

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
    _refreshCalendar();
  }

  /// Pulls the calendar overlay in the background (if a service is wired). A
  /// failed fetch is non-fatal — the dial just shows no events (local-first).
  Future<void> _refreshCalendar() async {
    final service = widget.calendarService;
    if (service == null) return;
    await service.loadSources(); // durable subscriptions (desktop)
    await service.refresh();
    if (mounted) setState(() {});
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

  /// Moves the selected wedge's **end** boundary (persisted). A move that would
  /// breach the 15-min minimum or cross a neighbor is rejected by core and left
  /// as a no-op.
  void _resizeSelectedEnd(int delta) {
    final id = _selectedId;
    if (id == null) return;
    final seg = _profile.segments[_indexOf(id)];
    try {
      _repo.updateBlock(id, endMin: seg.endMin + delta);
    } on InvalidProfileException {
      return;
    }
    setState(() => _profile = _repo.activeProfile());
    widget.onDayChanged?.call();
  }

  /// Moves the selected wedge's **start** boundary (the edge shared with the
  /// previous block). Same no-op-on-illegal contract as [_resizeSelectedEnd].
  void _resizeSelectedStart(int delta) {
    final id = _selectedId;
    if (id == null) return;
    final seg = _profile.segments[_indexOf(id)];
    try {
      _repo.updateBlock(id, startMin: seg.startMin + delta);
    } on InvalidProfileException {
      return;
    }
    setState(() => _profile = _repo.activeProfile());
    widget.onDayChanged?.call();
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
      widget.onDayChanged?.call();
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
      widget.onDayChanged?.call();
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
      widget.onDayChanged?.call();
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

  void _toggleTracking() {
    if (_tracking) {
      _stopTracking();
    } else {
      _startTracking();
    }
  }

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

  /// Today's calendar overlay: timed events as dial arcs (lane-packed by core),
  /// colored by their source.
  DayOverlay? get _overlay =>
      widget.calendarService?.provider.overlayOn(_today);

  List<OverlayArc> _overlayArcs() {
    final overlay = _overlay;
    final service = widget.calendarService;
    if (overlay == null || service == null) return const [];
    return [
      for (final e in overlay.timed)
        OverlayArc(
          startMin: e.startMin,
          endMin: e.endMin,
          track: e.track,
          colorHex: service.colorForSource(e.sourceId),
        ),
    ];
  }

  /// The hub's live-tracking descriptor, or null when idle.
  DialTracking? get _dialTracking {
    if (!_tracking) return null;
    return DialTracking(
      category: _trackCategory!,
      colorHex: _colorForCategory(_trackCategory!),
      elapsedLabel: _mmss(_elapsed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _shell(Size(constraints.maxWidth, constraints.maxHeight)),
        ),
      ),
    );
  }

  /// The radial shell: a large centered dial with everything else living in the
  /// margins and corners around it (the All-Dial law — the corners are the
  /// chrome budget).
  Widget _shell(Size box) {
    final double side = math.min(box.shortestSide * 0.82, 560.0);
    final dialRect = Rect.fromLTWH(
      (box.width - side) / 2,
      (box.height - side) / 2,
      side,
      side,
    );
    final sideInset = math.min(120.0, box.width * 0.22);

    return Stack(
      children: [
        // The instrument.
        Positioned.fromRect(
          rect: dialRect,
          child: DialView(
            profile: _profile,
            nowMin: _nowMin,
            mode: _mode,
            selectedSegmentId: _selectedId,
            actuals: _actualArcs(),
            overlay: _overlayArcs(),
            subBlocks: _subBlocks,
            tracking: _dialTracking,
            onSegmentTapped: (id) => setState(() => _selectedId = id),
            onHubTapped: _toggleTracking,
            onHubLongPressed: _openFocus,
            onBackgroundTapped: () {
              if (_selectedId != null) setState(() => _selectedId = null);
            },
          ),
        ),

        // All-day calendar events sit in the hub area, never on the ring.
        Positioned(
          top: 6,
          left: 12,
          right: 12,
          child: Center(child: _allDayBanner()),
        ),

        // Must-do tokens orbit above; habits perch below.
        Positioned(
          top: 40,
          left: sideInset,
          right: sideInset,
          child: Center(child: _trayChips()),
        ),
        Positioned(
          bottom: 48,
          left: sideInset,
          right: sideInset,
          child: Center(child: _habitPills()),
        ),

        // Mode toggle: unobtrusive, bottom-center.
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(child: _modeToggle()),
        ),

        // Four corner doors — the entire navigation surface.
        Positioned(
          top: 10,
          left: 10,
          child: _door(
            label: 'Plans',
            sub: 'templates · scope',
            onTap: _openPlansSheet,
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: _door(
            label: 'Insight',
            sub: 'stats · review',
            onTap: _openInsightSheet,
            alignEnd: true,
          ),
        ),
        Positioned(
          bottom: 10,
          left: 10,
          child: _door(
            label: 'Setup',
            sub: 'calendars · export',
            onTap: _openSetupSheet,
          ),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: _door(
            label: 'Agent',
            sub: 'MCP · stdio',
            onTap: _openAgent,
            alignEnd: true,
            statusDot: true,
          ),
        ),

        // The radial popover editor for the selected wedge.
        _wedgePopover(dialRect, box),
      ],
    );
  }

  void _openStats() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StatsScreen(repository: _repo)));
  }

  Future<void> _openFocus() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FocusScreen(
          repository: _repo,
          onLogged: () => setState(() => _logs = _repo.logs()),
        ),
      ),
    );
    setState(() => _logs = _repo.logs());
  }

  void _openReview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          repository: _repo,
          calendarService: widget.calendarService,
        ),
      ),
    );
  }

  Future<void> _openCalendars() async {
    final service = widget.calendarService;
    if (service == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarSettingsScreen(
          service: service,
          onChanged: () => setState(() {}), // redraw overlay
        ),
      ),
    );
    setState(() {}); // pick up any source/overlay changes on return
  }

  void _openAgent() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AgentScreen(host: widget.agentHost)),
    );
  }

  Future<void> _openTemplates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          repository: _repo,
          onChanged: () => setState(_loadFromRepo),
        ),
      ),
    );
    // The active template (and thus the ring) may have changed.
    setState(_loadFromRepo);
    widget.onDayChanged?.call();
  }

  /// Chooses what today's edits target: a per-date override ("this day") or the
  /// weekday template. Picking "this day" materializes an override (a deep copy
  /// that inherits the template's detail); the two stay in sync only until you
  /// edit the override.
  void _setEditScope({required bool template}) {
    if (template) {
      _repo.switchProfile(_repo.templateForDate(_today).id);
    } else {
      _repo.switchProfile(_repo.overrideForDate(_today).id);
    }
    setState(() {
      _selectedId = null;
      _loadFromRepo();
    });
    widget.onDayChanged?.call();
  }

  void _resetToTemplate() {
    _repo.resetDate(_today);
    setState(() {
      _selectedId = null;
      _loadFromRepo();
    });
    widget.onDayChanged?.call();
  }

  // ---- radial shell pieces --------------------------------------------------

  /// All-day calendar events sit in the hub area per SPEC §2.5 (never on the
  /// ring) — a compact chip row floated at the top of the dial.
  Widget _allDayBanner() {
    final overlay = _overlay;
    final service = widget.calendarService;
    if (overlay == null || service == null || overlay.allDay.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final e in overlay.allDay)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: parseHexColor(
                service.colorForSource(e.sourceId),
              ).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: parseHexColor(service.colorForSource(e.sourceId))
                    .withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event, size: 12),
                const SizedBox(width: 4),
                Text(e.title, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  static ShapeBorder _pillShape([Color? border]) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border ?? Colors.white.withValues(alpha: 0.12)),
      );

  Widget _trayChips() {
    final tray = trayFor(_today, _tasks, _completions);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final item in tray) _chip(item.task, item.doneToday),
        _addPill('Task', _addTaskDialog, keyOverride: const Key('add-task')),
      ],
    );
  }

  /// A must-do token: tap toggles done, long-press opens its actions. (The
  /// drag-onto-a-wedge placement from the prototype is a follow-up milestone.)
  Widget _chip(RecurringTask task, bool done) {
    final color = parseHexColor(task.colorHex);
    return GestureDetector(
      onLongPress: () => _taskActions(task),
      child: Material(
        color: const Color(0xF2141A2B),
        shape: _pillShape(),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleTask(task.id, done),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 15,
                  color: done ? color : Colors.white70,
                ),
                const SizedBox(width: 7),
                Text(
                  task.label,
                  style: TextStyle(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color:
                        done ? Colors.white.withValues(alpha: 0.4) : Colors.white,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addPill(String label, VoidCallback onTap, {Key? keyOverride}) {
    return Material(
      key: keyOverride,
      color: Colors.transparent,
      shape: _pillShape(Colors.white24),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 15, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _habitPills() {
    final counts = habitCountsFor(_today, _habits, _habitEvents);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final c in counts) _habitPill(c),
        _addPill('Habit', _addHabitDialog, keyOverride: const Key('add-habit')),
      ],
    );
  }

  /// A habit counter: tap +1, long-press −1.
  Widget _habitPill(HabitDayCount c) {
    final color = parseHexColor(c.habit.colorHex);
    final bad = c.habit.polarity == HabitPolarity.bad;
    final countText = c.target != null ? '${c.count} / ${c.target}' : '${c.count}';
    final reachedColor =
        bad ? const Color(0xFFB5624F) : const Color(0xFF6FA85B);
    return GestureDetector(
      onLongPress: c.count > 0 ? () => _bumpHabit(c.habit.id, -1) : null,
      child: Material(
        color: const Color(0xFF0E1322),
        shape: _pillShape(),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _bumpHabit(c.habit.id, 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(c.habit.label, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 7),
                Text(
                  countText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: c.targetReached ? reachedColor : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return SegmentedButton<DialMode>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: DialMode.compass, label: Text('Compass')),
        ButtonSegment(value: DialMode.clock, label: Text('Clock')),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
  }

  Widget _door({
    required String label,
    required String sub,
    required VoidCallback onTap,
    bool alignEnd = false,
    bool statusDot = false,
  }) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xFF6FA85B),
        shape: BoxShape.circle,
      ),
    );
    return Material(
      color: const Color(0xCC0E1322),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (statusDot && !alignEnd) ...[dot, const SizedBox(width: 6)],
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (statusDot && alignEnd) ...[const SizedBox(width: 6), dot],
                ],
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wedgePopover(Rect dialRect, Size box) {
    // A *positioned* placeholder when hidden: every direct child of the shell's
    // Stack is positioned, so the Stack expands to fill regardless of the parent
    // constraints (a non-positioned 0×0 child could otherwise collapse it).
    const hidden = Positioned(left: 0, top: 0, child: SizedBox.shrink());
    final id = _selectedId;
    if (id == null) return hidden;
    final idx = _indexOf(id);
    if (idx < 0) return hidden;
    final seg = _profile.segments[idx];

    final dialSize = Size(dialRect.width, dialRect.height);
    final rot = DialGeometry.rotationDeg(
      compass: _mode == DialMode.compass,
      nowMin: _nowMin,
    );
    final mid = DialGeometry.wedgeMidAngleDeg(
      startMin: seg.startMin,
      durationMin: seg.durationMin,
      rotationDeg: rot,
    );
    final a = DialGeometry.pointAt(dialSize, DialGeometry.ro + 26, mid);
    final anchor = Offset(dialRect.left + a.dx, dialRect.top + a.dy);

    const popW = 240.0;
    final maxH = math.min(360.0, box.height - 16);
    final left = (anchor.dx - popW / 2)
        .clamp(8.0, math.max(8.0, box.width - popW - 8))
        .toDouble();
    final top = (anchor.dy - maxH / 2)
        .clamp(8.0, math.max(8.0, box.height - maxH - 8))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: popW, maxHeight: maxH),
        child: Material(
          color: const Color(0xFF141A2B),
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: _popCard(seg),
        ),
      ),
    );
  }

  Widget _popCard(Segment seg) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: parseHexColor(seg.colorHex),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _editBlockDialog(seg),
                  child: Text(
                    seg.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: parseHexColor(seg.colorHex),
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Close',
                onPressed: () => setState(() => _selectedId = null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Text(
            '${formatMinuteOfDay(seg.startMin)}–${formatMinuteOfDay(seg.endMin)}'
            ' · ${formatDuration(seg.durationMin)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          _stepperRow(
            'START',
            formatMinuteOfDay(seg.startMin),
            onMinus: () => _resizeSelectedStart(-15),
            onPlus: () => _resizeSelectedStart(15),
            minusTip: 'Start earlier',
            plusTip: 'Start later',
          ),
          _stepperRow(
            'END',
            formatMinuteOfDay(seg.endMin),
            onMinus: () => _resizeSelectedEnd(-15),
            onPlus: () => _resizeSelectedEnd(15),
            minusTip: 'End earlier',
            plusTip: 'End later',
          ),
          _subBlockSection(seg),
          const SizedBox(height: 8),
          _ColorSwatches(
            selected: seg.colorHex,
            onChanged: (c) {
              _repo.updateBlock(seg.id, colorHex: c);
              setState(() => _profile = _repo.activeProfile());
              widget.onDayChanged?.call();
            },
          ),
          const Divider(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tap the name to rename',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
              TextButton.icon(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB5624F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperRow(
    String label,
    String value, {
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required String minusTip,
    required String plusTip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                color: Colors.white54,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: minusTip,
            onPressed: onMinus,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: plusTip,
            onPressed: onPlus,
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
        ],
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

  // ---- corner-door sheets ---------------------------------------------------

  Widget _sheetHeader(String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );

  Future<void> _openPlansSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E1322),
      builder: (ctx) {
        final editingTemplate = _profile.forDate == null;
        final hasOverride = _repo.profileForDate(_today).forDate != null;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHeader('Plans', 'templates · edit scope'),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Day templates'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openTemplates();
                },
              ),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Edit this day'),
                trailing: editingTemplate ? null : const Icon(Icons.check, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditScope(template: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat),
                title: const Text('Edit weekday template'),
                trailing: editingTemplate ? const Icon(Icons.check, size: 18) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setEditScope(template: true);
                },
              ),
              if (hasOverride)
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Reset this day to template'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resetToTemplate();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInsightSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E1322),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader('Insight', 'plan vs actual · review'),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('Plan vs actual'),
              onTap: () {
                Navigator.pop(ctx);
                _openStats();
              },
            ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Review'),
              onTap: () {
                Navigator.pop(ctx);
                _openReview();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSetupSheet() async {
    final hasCalendar = widget.calendarService != null;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E1322),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHeader('Setup', 'calendars · export'),
            if (hasCalendar)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Calendars'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCalendars();
                },
              )
            else
              const ListTile(
                leading: Icon(Icons.event_busy),
                title: Text('Calendars'),
                subtitle: Text('Not available in this build'),
                enabled: false,
              ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export'),
              subtitle: const Text('From the Review screen'),
              onTap: () {
                Navigator.pop(ctx);
                _openReview();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _taskActions(RecurringTask task) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0E1322),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(task.label, 'must-do today'),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit…'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        await _editTaskDialog(task);
      case 'archive':
        _archiveTask(task.id);
      case 'delete':
        _deleteTask(task.id);
    }
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
