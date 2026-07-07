import '../time/civil_date.dart';

/// A mirrored calendar event (SPEC §2.5 / §12.1) — read-only overlay data, never
/// a segment. Discrete, sparse, may overlap other events.
///
/// Times are ISO-8601 strings interpreted at their **own wall clock** (the
/// overlay shows an event at the time it reads); `core` is timezone-agnostic and
/// does not convert zones. An [allDay] event uses date-only semantics: [startTs]
/// is its first day at `T00:00:00`, [endTs] is the exclusive end day.
///
/// A parsed master event may carry a raw [rrule]; concrete instances produced by
/// expansion have `rrule == null`. Events live in a disposable cache, never in
/// the CRDT doc.
class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.sourceId,
    required this.uid,
    required this.title,
    required this.startTs,
    required this.endTs,
    this.allDay = false,
    this.rrule,
    this.calendarName,
  })  : start = DateTime.parse(startTs),
        end = DateTime.parse(endTs) {
    if (end.isBefore(start)) {
      throw ArgumentError('CalendarEvent end ($endTs) precedes start ($startTs)');
    }
  }

  /// Stable within a source. For a recurrence instance this includes the
  /// occurrence date so instances don't collide (see expansion).
  final String id;
  final String sourceId;

  /// The iCalendar UID (shared across a recurrence set).
  final String uid;
  final String title;
  final String startTs;
  final String endTs;
  final bool allDay;

  /// Raw RRULE string (e.g. `FREQ=WEEKLY;BYDAY=MO,WE`) for a master event, or
  /// null for a single event / an already-expanded instance.
  final String? rrule;
  final String? calendarName;

  final DateTime start;
  final DateTime end;

  int get durationMin => end.difference(start).inMinutes;
  bool get isRecurring => rrule != null;

  CalendarEvent copyWith({
    String? id,
    String? startTs,
    String? endTs,
    String? rrule,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        sourceId: sourceId,
        uid: uid,
        title: title,
        startTs: startTs ?? this.startTs,
        endTs: endTs ?? this.endTs,
        allDay: allDay,
        rrule: rrule,
        calendarName: calendarName,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'uid': uid,
        'title': title,
        'start': startTs,
        'end': endTs,
        'allDay': allDay,
        if (rrule != null) 'rrule': rrule,
        if (calendarName != null) 'calendar': calendarName,
      };

  factory CalendarEvent.fromJson(Map<String, Object?> j) => CalendarEvent(
        id: j['id'] as String,
        sourceId: j['sourceId'] as String,
        uid: j['uid'] as String,
        title: j['title'] as String,
        startTs: j['start'] as String,
        endTs: j['end'] as String,
        allDay: j['allDay'] as bool? ?? false,
        rrule: j['rrule'] as String?,
        calendarName: j['calendar'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.uid == uid &&
      other.title == title &&
      other.startTs == startTs &&
      other.endTs == endTs &&
      other.allDay == allDay &&
      other.rrule == rrule &&
      other.calendarName == calendarName;

  @override
  int get hashCode => Object.hash(
      id, sourceId, uid, title, startTs, endTs, allDay, rrule, calendarName);

  @override
  String toString() =>
      'CalendarEvent($id, "$title", $startTs–$endTs${allDay ? ' all-day' : ''})';
}

/// The civil date of an ISO-8601 timestamp's own wall clock (zone-agnostic:
/// reads the date fields directly, no conversion).
CivilDate wallDate(String isoTs) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(isoTs.trim());
  if (m == null) throw FormatException('Not an ISO timestamp', isoTs);
  return CivilDate(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// The minute-of-day of an ISO-8601 timestamp's own wall clock, `[0,1440)`.
/// A bare date (no time part) is midnight.
int wallMinute(String isoTs) {
  final m = RegExp(r'T(\d{2}):(\d{2})').firstMatch(isoTs);
  if (m == null) return 0;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}
