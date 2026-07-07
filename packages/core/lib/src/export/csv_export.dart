import '../models/time_log.dart';
import '../stats/plan_vs_actual.dart';

/// CSV export (SPEC §12.3). Minimal RFC 4180: fields containing a comma,
/// double-quote, or newline are wrapped in double-quotes with embedded quotes
/// doubled. Rows are joined with CRLF, the RFC's line terminator.
String _cell(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(RegExp('[",\r\n]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _row(List<Object?> cells) => cells.map(_cell).join(',');

String _csv(List<String> header, Iterable<List<Object?>> rows) {
  final buf = StringBuffer(_row(header));
  for (final r in rows) {
    buf.write('\r\n');
    buf.write(_row(r));
  }
  return buf.toString();
}

/// Actual time logs as CSV: one row per log, columns matching the `time_logs`
/// model (SPEC §5). Header always present so an empty log set still exports a
/// valid, self-describing file.
String timeLogsToCsv(Iterable<TimeLog> logs) => _csv(
      const [
        'date',
        'start',
        'end',
        'durationMin',
        'category',
        'segmentId',
        'note',
        'source',
      ],
      [
        for (final l in logs)
          [
            l.date.iso,
            l.startTs,
            l.endTs,
            l.durationMin,
            l.category,
            l.segmentId ?? '',
            l.note ?? '',
            l.source.name,
          ],
      ],
    );

/// Plan-vs-actual variance as CSV: one row per category (SPEC §4/§12.7).
String varianceToCsv(Iterable<CategoryVariance> variance) => _csv(
      const ['category', 'plannedMin', 'actualMin', 'deltaMin'],
      [
        for (final v in variance)
          [v.category, v.plannedMin, v.actualMin, v.deltaMin],
      ],
    );
