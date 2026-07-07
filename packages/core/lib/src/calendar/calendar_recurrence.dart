import '../time/civil_date.dart';
import 'calendar_event.dart';

/// Expands a recurring [event]'s RRULE into concrete instances whose start date
/// falls within `[from, to]` inclusive (SPEC §12.1). Non-recurring events pass
/// through if they intersect the window.
///
/// Supported: `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY`, `INTERVAL`, `COUNT`, `UNTIL`,
/// and `BYDAY` (weekly). Each instance keeps the master's time-of-day and
/// duration; only the date shifts. `COUNT` is honoured from the true first
/// occurrence even when it precedes the window. Unsupported parts are ignored,
/// which at worst over-produces (a harmless read-only overlay).
List<CalendarEvent> expandRecurring(
  CalendarEvent event, {
  required CivilDate from,
  required CivilDate to,
}) {
  if (!event.isRecurring) {
    // Keep it if any part of its span touches the window.
    final startDate = wallDate(event.startTs);
    final endDate = wallDate(event.endTs);
    if (endDate.isBefore(from) || startDate.isAfter(to)) return const [];
    return [event];
  }

  final rule = _Rule.parse(event.rrule!);
  final startDate = wallDate(event.startTs);
  final durationDays = startDate.daysUntil(wallDate(event.endTs));
  final startMin = _timePart(event.startTs);
  final endMin = _timePart(event.endTs);

  final out = <CalendarEvent>[];
  var produced = 0;
  const safetyCap = 3700; // ~10 years of daily events

  for (final d in _dates(startDate, rule, windowEnd: to, cap: safetyCap)) {
    produced++;
    if (rule.count != null && produced > rule.count!) break;
    if (rule.until != null) {
      if (d.isAfter(rule.until!)) break;
      if (d == rule.until! && startMin > rule.untilMinute) break;
    }
    if (d.isAfter(to)) break;
    if (d.isBefore(from)) continue;

    final s = _isoAt(d, startMin, _hasZone(event.startTs));
    final e = _isoAt(d.addDays(durationDays), endMin, _hasZone(event.endTs));
    out.add(event.copyWith(
      id: '${event.id}@${d.iso}',
      startTs: s,
      endTs: e,
      rrule: null,
    ));
  }
  return out;
}

/// Chronological occurrence dates from [start], bounded by [windowEnd] and
/// [cap]. COUNT/UNTIL are applied by the caller (which counts from the true
/// first occurrence).
Iterable<CivilDate> _dates(
  CivilDate start,
  _Rule rule, {
  required CivilDate windowEnd,
  required int cap,
}) sync* {
  switch (rule.freq) {
    case _Freq.daily:
      var d = start;
      var n = 0;
      while (!d.isAfter(windowEnd) && n < cap) {
        yield d;
        d = d.addDays(rule.interval);
        n++;
      }
    case _Freq.weekly:
      final days =
          rule.byDay.isNotEmpty ? rule.byDay : {start.weekday};
      final startMonday = start.addDays(-(start.weekday - 1));
      var d = start;
      var n = 0;
      while (!d.isAfter(windowEnd) && n < cap) {
        if (days.contains(d.weekday)) {
          final monday = d.addDays(-(d.weekday - 1));
          final weeksSince = startMonday.daysUntil(monday) ~/ 7;
          if (weeksSince % rule.interval == 0 && !d.isBefore(start)) {
            yield d;
          }
        }
        d = d.addDays(1);
        n++;
      }
    case _Freq.monthly:
      var year = start.year;
      var month = start.month;
      final dom = start.day;
      var n = 0;
      while (n < cap) {
        final d = _safeDate(year, month, dom);
        if (d != null) {
          if (d.isAfter(windowEnd)) break;
          yield d;
        }
        month += rule.interval;
        while (month > 12) {
          month -= 12;
          year++;
        }
        n++;
        if (_safeDate(year, month, 1)!.isAfter(windowEnd)) break;
      }
    case _Freq.yearly:
      var year = start.year;
      var n = 0;
      while (n < cap) {
        final d = _safeDate(year, start.month, start.day);
        if (d != null) {
          if (d.isAfter(windowEnd)) break;
          yield d;
        }
        year += rule.interval;
        n++;
      }
  }
}

CivilDate? _safeDate(int year, int month, int day) {
  final dt = DateTime.utc(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return CivilDate(year, month, day);
}

enum _Freq { daily, weekly, monthly, yearly }

class _Rule {
  _Rule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.until,
    this.untilMinute = 0,
    this.byDay = const {},
  });

  final _Freq freq;
  final int interval;
  final int? count;

  /// UNTIL as a date plus its minute-of-day ([untilMinute]); an instance is
  /// excluded once it starts strictly after this instant.
  final CivilDate? until;
  final int untilMinute;
  final Set<int> byDay; // ISO weekdays 1..7

  static _Rule parse(String rrule) {
    final parts = <String, String>{};
    for (final chunk in rrule.split(';')) {
      final eq = chunk.indexOf('=');
      if (eq == -1) continue;
      parts[chunk.substring(0, eq).toUpperCase()] = chunk.substring(eq + 1);
    }
    final freq = switch ((parts['FREQ'] ?? 'DAILY').toUpperCase()) {
      'WEEKLY' => _Freq.weekly,
      'MONTHLY' => _Freq.monthly,
      'YEARLY' => _Freq.yearly,
      _ => _Freq.daily,
    };
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    final count = int.tryParse(parts['COUNT'] ?? '');
    final untilRaw = parts['UNTIL'];
    final until = _parseUntil(untilRaw);
    final untilMinute = _parseUntilMinute(untilRaw);
    final byDay = <int>{
      for (final t in (parts['BYDAY'] ?? '').split(','))
        if (_weekdayCode[t.trim().toUpperCase()] != null)
          _weekdayCode[t.trim().toUpperCase()]!,
    };
    return _Rule(
      freq: freq,
      interval: interval < 1 ? 1 : interval,
      count: count,
      until: until,
      untilMinute: untilMinute,
      byDay: byDay,
    );
  }

  static const _weekdayCode = {
    'MO': 1,
    'TU': 2,
    'WE': 3,
    'TH': 4,
    'FR': 5,
    'SA': 6,
    'SU': 7,
  };

  static CivilDate? _parseUntil(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(v.trim());
    if (m == null) return null;
    return CivilDate(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  static int _parseUntilMinute(String? v) {
    if (v == null) return 0;
    final m = RegExp(r'T(\d{2})(\d{2})').firstMatch(v.trim());
    if (m == null) return 0;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }
}

int _timePart(String iso) {
  final m = RegExp(r'T(\d{2}):(\d{2})').firstMatch(iso);
  if (m == null) return 0;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

bool _hasZone(String iso) => iso.endsWith('Z');

String _isoAt(CivilDate d, int minute, bool utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hh = two(minute ~/ 60);
  final mm = two(minute % 60);
  return '${d.iso}T$hh:$mm:00${utc ? 'Z' : ''}';
}
