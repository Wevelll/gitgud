import 'dart:async';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../painters/dial_painter.dart';
import '../widgets/dial_view.dart';

/// The main dial screen: the dial plus its controls, a resize editor, and the
/// must-do tray. State is minimal `setState`; all reads/writes go through a
/// [DayRepository] (CLAUDE.md: the UI is wiring; logic + persistence live
/// behind the repository).
class DialScreen extends StatefulWidget {
  const DialScreen({super.key, required this.repository});

  final DayRepository repository;

  @override
  State<DialScreen> createState() => _DialScreenState();
}

class _DialScreenState extends State<DialScreen> {
  DayRepository get _repo => widget.repository;

  late DayProfile _profile;
  late List<RecurringTask> _tasks;
  late List<TaskCompletion> _completions;
  late List<Habit> _habits;
  late List<HabitEvent> _habitEvents;

  DialMode _mode = DialMode.compass;
  bool _live = true;
  int _nowMin = _minuteOfNow();
  String? _selectedId;

  final CivilDate _today = CivilDate.fromDateTime(DateTime.now());
  Timer? _timer;

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
    _tasks = _repo.tasks();
    _completions = _repo.completions();
    _habits = _repo.habits();
    _habitEvents = _repo.habitEvents();
  }

  void _startClock() {
    _timer?.cancel();
    if (!_live) return;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
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

  Widget _header(Segment cur) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR DAY · 24H',
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
        onSegmentTapped: (id) => setState(() => _selectedId = id),
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
          ? Text(
              'Tap a wedge to resize it',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Builder(
                  builder: (_) {
                    final seg = _profile.segments[_indexOf(id)];
                    return Column(
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
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => _resizeSelected(-15),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _resizeSelected(15),
                      icon: const Icon(Icons.add),
                    ),
                  ],
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
          Text(
            'MUST-DO TODAY · NO FIXED TIME',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 8),
          if (tray.isEmpty)
            Text(
              'Nothing due today',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          for (final item in tray)
            InkWell(
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
                    Text(
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
                  ],
                ),
              ),
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
