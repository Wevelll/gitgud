import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../painters/dial_painter.dart' show parseHexColor;

/// A session-by-session look at past days: pick a date, see what was actually
/// tracked (SPEC §4). Complements the Stats screen's aggregates.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repository});

  final DayRepository repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _panel = Color(0xFF0E1322);
  static const _daysBack = 14;
  static const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late final CivilDate _today = CivilDate.fromDateTime(DateTime.now());
  late CivilDate _selected = _today;

  List<TimeLog> _logsFor(CivilDate date) {
    final logs = widget.repository.logs().where((l) => l.date == date).toList();
    logs.sort((a, b) => a.start.compareTo(b.start));
    return logs;
  }

  String _colorForCategory(String category) {
    for (final s in widget.repository.activeProfile().segments) {
      if (s.name == category) return s.colorHex;
    }
    return '#F2E9D8';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logsFor(_selected);
    final tracked = logs.fold<int>(0, (a, l) => a + l.durationMin);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('History'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dateStrip(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '${_selected.iso} · ${formatDuration(tracked)} tracked',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: logs.isEmpty
                      ? _empty()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [for (final l in logs) _sessionRow(l)],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateStrip() {
    // Newest (today) first, going back _daysBack days.
    final dates = [for (var i = 0; i < _daysBack; i++) _today.addDays(-i)];
    return SizedBox(
      height: 74,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [for (final d in dates) _dateChip(d)],
      ),
    );
  }

  Widget _dateChip(CivilDate d) {
    final selected = d == _selected;
    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E8B8B) : _panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekday[d.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? const Color(0xFF04140F)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF04140F) : Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nothing was tracked on this day.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _sessionRow(TimeLog log) {
    final color = parseHexColor(_colorForCategory(log.category));
    final start = log.start.toLocal();
    final end = log.end.toLocal();
    final range = '${_hhmm(start)}–${_hhmm(end)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.category,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  range,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatDuration(log.durationMin),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
