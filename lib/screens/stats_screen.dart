import 'dart:math' as math;

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

import '../painters/dial_painter.dart' show parseHexColor;
import 'history_screen.dart';

/// The range a stats view covers.
enum StatsRange { day, week, month }

/// Plan-vs-actual insights (SPEC §4): per-category planned vs tracked time over
/// a range, computed entirely by `core`'s [planVsActual]. Pays off the tracking
/// that feeds it.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.repository});

  final DayRepository repository;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsRange _range = StatsRange.day;

  int _spanDays(StatsRange r) => switch (r) {
    StatsRange.day => 0,
    StatsRange.week => 6,
    StatsRange.month => 29,
  };

  List<CategoryVariance> _variance() {
    final today = CivilDate.fromDateTime(DateTime.now());
    final dates = today.addDays(-_spanDays(_range)).rangeTo(today);
    return planVsActual(
      dates: dates,
      profileForDate: (_) => widget.repository.activeProfile(),
      logs: widget.repository.logs(),
    );
  }

  String _colorForCategory(String category) {
    for (final s in widget.repository.activeProfile().segments) {
      if (s.name == category) return s.colorHex;
    }
    return '#F2E9D8';
  }

  @override
  Widget build(BuildContext context) {
    final variance = _variance();
    // Categories that were both never planned and never tracked add nothing.
    final rows = variance
        .where((v) => v.plannedMin > 0 || v.actualMin > 0)
        .toList();
    final maxMin = rows.fold<int>(
      1,
      (m, v) => math.max(m, math.max(v.plannedMin, v.actualMin)),
    );
    final totalPlanned = rows.fold<int>(0, (a, v) => a + v.plannedMin);
    final totalActual = rows.fold<int>(0, (a, v) => a + v.actualMin);
    final tracked = rows.any((v) => v.actualMin > 0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Plan vs actual'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(repository: widget.repository),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _rangePicker(),
                const SizedBox(height: 16),
                _summary(totalPlanned, totalActual),
                const SizedBox(height: 12),
                if (!tracked)
                  _emptyHint()
                else
                  for (final v in rows) _categoryCard(v, maxMin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangePicker() {
    return SegmentedButton<StatsRange>(
      segments: const [
        ButtonSegment(value: StatsRange.day, label: Text('Day')),
        ButtonSegment(value: StatsRange.week, label: Text('Week')),
        ButtonSegment(value: StatsRange.month, label: Text('Month')),
      ],
      selected: {_range},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _range = s.first),
    );
  }

  Widget _summary(int planned, int actual) {
    final delta = actual - planned;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat('Tracked', formatDuration(actual)),
          _stat('Planned', formatDuration(planned)),
          _stat('Δ', _deltaLabel(delta), color: _deltaColor(delta)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            color: context.inkAlpha(0.45),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color ?? context.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _emptyHint() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Nothing tracked in this range yet.\n'
        'Use Start on the dial to time a block, and it shows up here.',
        style: TextStyle(color: context.inkAlpha(0.55)),
      ),
    );
  }

  Widget _categoryCard(CategoryVariance v, int maxMin) {
    final color = parseHexColor(_colorForCategory(v.category));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                v.category,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              Text(
                _deltaLabel(v.deltaMin),
                style: TextStyle(
                  color: _deltaColor(v.deltaMin),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _barRow('Tracked', v.actualMin, maxMin, color),
          const SizedBox(height: 6),
          _barRow('Planned', v.plannedMin, maxMin, context.inkAlpha(0.28)),
        ],
      ),
    );
  }

  Widget _barRow(String label, int minutes, int maxMin, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: context.inkAlpha(0.45)),
          ),
        ),
        Expanded(
          child: Container(
            height: 9,
            decoration: BoxDecoration(
              color: context.inkAlpha(0.06),
              borderRadius: BorderRadius.circular(5),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (minutes / maxMin).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            formatDuration(minutes),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  String _deltaLabel(int d) {
    if (d == 0) return 'on plan';
    return d > 0 ? '+${formatDuration(d)}' : '−${formatDuration(-d)}';
  }

  Color _deltaColor(int d) {
    if (d == 0) return context.inkAlpha(0.5);
    // Over plan reads warm, under plan reads cool — informative, not a verdict.
    return d > 0 ? const Color(0xFFC98A3E) : const Color(0xFF5A9FB0);
  }
}
