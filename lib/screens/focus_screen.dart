import 'dart:async';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

import '../painters/dial_painter.dart' show parseHexColor;

/// A focus timer (SPEC §12.6): pick a length, run a countdown bound to the
/// current block, and on completion (or an early finish) log a
/// [LogSource.timer] actual through `core`'s [FocusSession]. The timer is
/// UI-local; the durable artifact is the logged actual.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.repository, this.onLogged});

  final DayRepository repository;

  /// Called after a session logs an actual, so the caller can refresh.
  final VoidCallback? onLogged;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

enum _Phase { idle, running, done }

class _FocusScreenState extends State<FocusScreen> {
  static const _presets = [15, 25, 45, 60];

  int _minutes = 25;
  _Phase _phase = _Phase.idle;
  int _remaining = 0; // seconds
  Timer? _timer;
  String? _startTs;
  int _loggedMinutes = 0;

  late final Segment _segment = widget.repository.activeProfile().segmentAt(
    _nowMin(),
  );

  static int _nowMin() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _startTs = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _phase = _Phase.running;
      _remaining = _minutes * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _finish();
    });
  }

  /// Ends the session and logs the elapsed time as a timer actual.
  void _finish() {
    _timer?.cancel();
    final start = _startTs;
    if (start == null) return;
    final session = FocusSession(
      category: _segment.name,
      startTs: start,
      segmentId: _segment.id,
    );
    final pending = session.completeAt(
      DateTime.now().toUtc().toIso8601String(),
    );
    widget.repository.logActual(
      category: pending.category,
      startTs: pending.startTs,
      endTs: pending.endTs,
      segmentId: pending.segmentId,
      source: pending.source,
    );
    widget.onLogged?.call();
    setState(() {
      _phase = _Phase.done;
      _loggedMinutes = pending.durationMin;
    });
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  String _mmss(int seconds) {
    final s = seconds.clamp(0, 1 << 31);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(_segment.colorHex);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Focus'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'FOCUS ON',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: context.inkAlpha(0.45),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _segment.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_phase == _Phase.idle) ..._idle(color),
                  if (_phase == _Phase.running) ..._running(color),
                  if (_phase == _Phase.done) ..._done(color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _idle(Color color) => [
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (final m in _presets)
          ChoiceChip(
            label: Text('$m min'),
            selected: _minutes == m,
            onSelected: (_) => setState(() => _minutes = m),
          ),
      ],
    ),
    const SizedBox(height: 28),
    FilledButton.icon(
      onPressed: _start,
      icon: const Icon(Icons.play_arrow),
      label: Text('Start $_minutes-min focus'),
    ),
  ];

  List<Widget> _running(Color color) => [
    Text(
      _mmss(_remaining),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w700,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    const SizedBox(height: 8),
    LinearProgressIndicator(
      value: _minutes == 0 ? 0 : 1 - (_remaining / (_minutes * 60)),
      color: color,
      backgroundColor: context.inkAlpha(0.08),
    ),
    const SizedBox(height: 28),
    FilledButton.tonal(
      onPressed: _finish,
      child: const Text('Finish now (log it)'),
    ),
    const SizedBox(height: 8),
    TextButton(onPressed: _cancel, child: const Text('Cancel')),
  ];

  List<Widget> _done(Color color) => [
    Icon(Icons.check_circle, color: color, size: 48),
    const SizedBox(height: 12),
    Text(
      'Logged ${formatDuration(_loggedMinutes)} of ${_segment.name}',
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: () => setState(() => _phase = _Phase.idle),
      child: const Text('Another'),
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Done'),
    ),
  ];
}
