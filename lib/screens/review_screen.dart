import 'dart:convert';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../calendar/calendar_service.dart';
import '../export/exporter.dart';
import '../painters/dial_painter.dart' show parseHexColor;

/// Periodic review (SPEC §12.7): a week / month / year look-back over the
/// primitives already in `core` — task completion, streaks, calendar load, and
/// plan-vs-actual — all computed by [buildReview]. Read-only; no new state.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.repository,
    this.calendarService,
    this.exporter,
  });

  final DayRepository repository;
  final CalendarService? calendarService;

  /// File-export seam (SPEC §12.3). Defaults to the platform exporter; tests
  /// inject a fake.
  final Exporter? exporter;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ReviewRange _range = ReviewRange.week;

  static const _panel = Color(0xFF0E1322);

  DayRepository get _repo => widget.repository;

  late final Exporter _exporter = widget.exporter ?? createExporter();

  Future<void> _export(String kind) async {
    final today = CivilDate.fromDateTime(DateTime.now()).iso;
    final (String name, String contents) = switch (kind) {
      'csv' => ('daydial-logs-$today.csv', timeLogsToCsv(_repo.logs())),
      'ics' => ('daydial-logs-$today.ics', timeLogsToIcs(_repo.logs())),
      _ => (
          'daydial-backup-$today.json',
          const JsonEncoder.withIndent('  ').convert(_repo.snapshot().toJson()),
        ),
    };
    try {
      final where = await _exporter.save(name, contents);
      if (mounted) _toast('Saved $name to $where');
    } catch (e) {
      if (mounted) _toast('Export failed: $e');
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  PeriodicReview _review() {
    final today = CivilDate.fromDateTime(DateTime.now());
    return buildReview(
      range: _range,
      asOf: today,
      profileForDate: _repo.profileForDate,
      logs: _repo.logs(),
      tasks: _repo.tasks(),
      completions: _repo.completions(),
      habits: _repo.habits(),
      habitEvents: _repo.habitEvents(),
      calendar: widget.calendarService?.provider,
    );
  }

  @override
  Widget build(BuildContext context) {
    final review = _review();
    final hasCalendar = widget.calendarService != null;
    final streaks = [...review.taskStreaks, ...review.habitStreaks]
      ..sort((a, b) => b.streak.current.compareTo(a.streak.current));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Review'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _rangePicker(),
                const SizedBox(height: 8),
                Text(
                  '${review.from.iso} → ${review.to.iso}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 16),
                _summary(review, hasCalendar),
                const SizedBox(height: 16),
                _sectionLabel('STREAKS'),
                if (streaks.isEmpty)
                  _hint('No recurring tasks or habits yet.')
                else
                  for (final s in streaks) _streakRow(s),
                const SizedBox(height: 16),
                _sectionLabel('TIME BY CATEGORY'),
                if (review.variance.every((v) => v.actualMin == 0))
                  _hint('Nothing tracked in this range yet.')
                else
                  for (final v in review.variance)
                    if (v.plannedMin > 0 || v.actualMin > 0) _varianceRow(v),
                const SizedBox(height: 16),
                _sectionLabel('EXPORT'),
                _exportBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangePicker() {
    return SegmentedButton<ReviewRange>(
      segments: const [
        ButtonSegment(value: ReviewRange.week, label: Text('Week')),
        ButtonSegment(value: ReviewRange.month, label: Text('Month')),
        ButtonSegment(value: ReviewRange.year, label: Text('Year')),
      ],
      selected: {_range},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _range = s.first),
    );
  }

  Widget _summary(PeriodicReview review, bool hasCalendar) {
    final pct = (review.taskCompletionRate * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat(
            'Tasks done',
            review.dueTaskInstances == 0
                ? '—'
                : '${review.completedTaskInstances}/${review.dueTaskInstances}',
            sub: review.dueTaskInstances == 0 ? null : '$pct%',
          ),
          _stat('Tracked', formatDuration(_trackedTotal(review))),
          if (hasCalendar)
            _stat('Booked', formatDuration(review.calendarMinutes)),
        ],
      ),
    );
  }

  int _trackedTotal(PeriodicReview review) =>
      review.variance.fold(0, (a, v) => a + v.actualMin);

  Widget _stat(String label, String value, {String? sub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (sub != null)
          Text(
            sub,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }

  Widget _exportBar() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _export('csv'),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Logs CSV'),
          ),
          OutlinedButton.icon(
            onPressed: () => _export('ics'),
            icon: const Icon(Icons.event_note_outlined, size: 18),
            label: const Text('Logs ICS'),
          ),
          OutlinedButton.icon(
            onPressed: () => _export('json'),
            icon: const Icon(Icons.data_object, size: 18),
            label: const Text('Backup JSON'),
          ),
        ],
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      );

  Widget _hint(String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
      );

  Widget _streakRow(NamedStreak s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(s.label, overflow: TextOverflow.ellipsis),
          ),
          _pill(
            '🔥 ${s.streak.current}',
            s.streak.current > 0
                ? const Color(0xFFC98A3E)
                : Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          _pill(
            'best ${s.streak.longest}',
            Colors.white.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  Widget _varianceRow(CategoryVariance v) {
    final color = parseHexColor(_colorForCategory(v.category));
    final d = v.deltaMin;
    final deltaLabel = d == 0
        ? 'on plan'
        : (d > 0 ? '+${formatDuration(d)}' : '−${formatDuration(-d)}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(v.category, overflow: TextOverflow.ellipsis)),
          Text(
            '${formatDuration(v.actualMin)} / ${formatDuration(v.plannedMin)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              deltaLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: d == 0
                    ? Colors.white.withValues(alpha: 0.5)
                    : (d > 0
                        ? const Color(0xFFC98A3E)
                        : const Color(0xFF5A9FB0)),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _colorForCategory(String category) {
    for (final s in _repo.activeProfile().segments) {
      if (s.name == category) return s.colorHex;
    }
    return '#F2E9D8';
  }
}
