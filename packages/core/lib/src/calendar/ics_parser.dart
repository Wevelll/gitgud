import 'calendar_event.dart';

/// A minimal iCalendar (RFC 5545) reader for the read-only overlay (SPEC §12.1).
///
/// Scope is deliberately small but correct for the common cases: line
/// unfolding, VEVENT extraction, SUMMARY/UID/DTSTART/DTEND, all-day
/// (`VALUE=DATE`) vs timed events, UTC (`Z`) vs floating times, and capturing
/// RRULE (expansion lives in `calendar_recurrence.dart`). Unknown properties are
/// ignored. Timezone databases (VTIMEZONE) are not interpreted — a `TZID` time
/// is read at its wall clock, matching how the overlay draws it.
List<CalendarEvent> icsToEvents(String ics, {required String sourceId}) {
  final lines = _unfold(ics);
  final events = <CalendarEvent>[];

  Map<String, String>? cur; // property name (upper) -> raw value
  Map<String, String>? curParams; // property name -> its parameter blob
  for (final line in lines) {
    final trimmed = line.trimRight();
    if (trimmed == 'BEGIN:VEVENT') {
      cur = {};
      curParams = {};
      continue;
    }
    if (trimmed == 'END:VEVENT') {
      if (cur != null) {
        final e = _buildEvent(cur, curParams!, sourceId);
        if (e != null) events.add(e);
      }
      cur = null;
      curParams = null;
      continue;
    }
    if (cur == null) continue;

    final colon = trimmed.indexOf(':');
    if (colon == -1) continue;
    final lhs = trimmed.substring(0, colon);
    final value = trimmed.substring(colon + 1);
    final semi = lhs.indexOf(';');
    final name = (semi == -1 ? lhs : lhs.substring(0, semi)).toUpperCase();
    final params = semi == -1 ? '' : lhs.substring(semi + 1);
    cur[name] = value;
    curParams![name] = params.toUpperCase();
  }
  return events;
}

/// Joins RFC 5545 folded lines: a line beginning with a space or tab is a
/// continuation of the previous one.
List<String> _unfold(String ics) {
  final raw = ics.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <String>[];
  for (final line in raw) {
    if (line.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
      if (out.isNotEmpty) out[out.length - 1] += line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

CalendarEvent? _buildEvent(
  Map<String, String> props,
  Map<String, String> params,
  String sourceId,
) {
  final dtStart = props['DTSTART'];
  if (dtStart == null) return null;
  final startIsDate = (params['DTSTART'] ?? '').contains('VALUE=DATE') &&
      !dtStart.contains('T');
  final start = _parseIcsTime(dtStart);
  if (start == null) return null;

  String endIso;
  bool allDay = startIsDate;
  final dtEnd = props['DTEND'];
  if (dtEnd != null) {
    final endIsDate = (params['DTEND'] ?? '').contains('VALUE=DATE') &&
        !dtEnd.contains('T');
    final end = _parseIcsTime(dtEnd);
    if (end == null) return null;
    endIso = end.iso;
    allDay = startIsDate && endIsDate;
  } else if (startIsDate) {
    // All-day with no DTEND defaults to a single day (exclusive next day).
    endIso = _addDaysIso(start.iso, 1);
  } else {
    // Timed with no DTEND: zero-length instant.
    endIso = start.iso;
  }

  final title = _unescapeText(props['SUMMARY'] ?? '(no title)');
  final uid = props['UID'] ?? '${start.iso}-$title';
  return CalendarEvent(
    id: '$sourceId:$uid',
    sourceId: sourceId,
    uid: uid,
    title: title,
    startTs: start.iso,
    endTs: endIso,
    allDay: allDay,
    rrule: props['RRULE'],
  );
}

class _IcsTime {
  _IcsTime(this.iso);
  final String iso;
}

/// Parses an iCalendar date or date-time into an ISO-8601 string. Handles
/// `YYYYMMDD` (date), `YYYYMMDDTHHMMSS` (floating), and a trailing `Z` (UTC).
_IcsTime? _parseIcsTime(String raw) {
  final v = raw.trim();
  final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
  if (dateOnly != null) {
    return _IcsTime(
        '${dateOnly.group(1)}-${dateOnly.group(2)}-${dateOnly.group(3)}T00:00:00');
  }
  final dt = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
      .firstMatch(v);
  if (dt == null) return null;
  final z = dt.group(7) == 'Z' ? 'Z' : '';
  return _IcsTime('${dt.group(1)}-${dt.group(2)}-${dt.group(3)}'
      'T${dt.group(4)}:${dt.group(5)}:${dt.group(6)}$z');
}

String _addDaysIso(String iso, int days) {
  final d = DateTime.parse(iso).add(Duration(days: days));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
      'T00:00:00';
}

/// Reverses RFC 5545 TEXT escaping.
String _unescapeText(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[i + 1];
      switch (n) {
        case 'n':
        case 'N':
          buf.write('\n');
        case r'\':
          buf.write(r'\');
        case ';':
          buf.write(';');
        case ',':
          buf.write(',');
        default:
          buf.write(n);
      }
      i++;
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}
