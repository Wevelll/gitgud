import '../models/day_profile.dart';
import '../models/time_log.dart';
import '../time/civil_date.dart';

/// iCalendar (ICS, RFC 5545) export (SPEC §12.3), so a Day-Dial day or its
/// actuals can be read by any calendar app.
///
/// This is intentionally small: single (non-recurring) VEVENTs, UTC timestamps
/// in the basic `YYYYMMDDTHHMMSSZ` form, TEXT values escaped and long lines
/// folded per §3 of the RFC. It is the mirror image of [icsToEvents] on the
/// import side (calendar overlay).

const String _prodId = '-//Day-Dial//Export//EN';

/// Escapes a TEXT value (RFC 5545 §3.3.11): backslash, semicolon, comma, and
/// newlines.
String _escapeText(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\n');

/// Folds a content line to <=75 octets by inserting CRLF + a space (RFC 5545
/// §3.1). Works on code units; adequate for the ASCII/BMP content we emit.
String _fold(String line) {
  if (line.length <= 75) return line;
  final buf = StringBuffer();
  var i = 0;
  while (line.length - i > 75) {
    buf.write(line.substring(i, i + 75));
    buf.write('\r\n ');
    i += 75;
  }
  buf.write(line.substring(i));
  return buf.toString();
}

/// Formats an instant as UTC basic time `YYYYMMDDTHHMMSSZ`.
String _utcStamp(DateTime dt) {
  final u = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

class _Event {
  _Event({
    required this.uid,
    required this.summary,
    required this.start,
    required this.end,
  });
  final String uid;
  final String summary;
  final DateTime start;
  final DateTime end;
}

String _vevent(_Event e, DateTime stamp) {
  final lines = <String>[
    'BEGIN:VEVENT',
    'UID:${e.uid}',
    'DTSTAMP:${_utcStamp(stamp)}',
    'DTSTART:${_utcStamp(e.start)}',
    'DTEND:${_utcStamp(e.end)}',
    'SUMMARY:${_escapeText(e.summary)}',
    'END:VEVENT',
  ];
  return lines.map(_fold).join('\r\n');
}

String _calendar(Iterable<_Event> events, DateTime stamp) {
  final buf = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\n')
    ..write('VERSION:2.0\r\n')
    ..write('PRODID:$_prodId\r\n');
  for (final e in events) {
    buf.write(_vevent(e, stamp));
    buf.write('\r\n');
  }
  buf.write('END:VCALENDAR');
  return buf.toString();
}

/// The segments of [profile] on [date] as a VCALENDAR — the planned day as
/// timed events. A segment that wraps midnight ends on the following calendar
/// day (its instant math is unaffected). [dtStamp] is the generation time
/// (defaults to now); pass a fixed value for deterministic output/tests.
String segmentsToIcs(
  DayProfile profile,
  CivilDate date, {
  DateTime? dtStamp,
}) {
  final stamp = dtStamp ?? DateTime.now();
  DateTime at(CivilDate d, int minute) =>
      DateTime.utc(d.year, d.month, d.day).add(Duration(minutes: minute));
  final events = [
    for (final s in profile.segments)
      _Event(
        uid: '${s.id}@${date.iso}.daydial',
        summary: s.name,
        start: at(date, s.startMin),
        // Wrap: end lands on the next day; duration is the clockwise span.
        end: at(date, s.startMin + s.durationMin),
      ),
  ];
  return _calendar(events, stamp);
}

/// Actual time logs as a VCALENDAR (SPEC §12.3) — what actually happened, as
/// timed events. [dtStamp] defaults to now.
String timeLogsToIcs(Iterable<TimeLog> logs, {DateTime? dtStamp}) {
  final stamp = dtStamp ?? DateTime.now();
  final events = [
    for (final l in logs)
      _Event(
        uid: '${l.id}.daydial',
        summary: l.category,
        start: l.start,
        end: l.end,
      ),
  ];
  return _calendar(events, stamp);
}
