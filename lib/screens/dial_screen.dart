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
                child: Text(_live ? '● Live' : 'Live'),
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
