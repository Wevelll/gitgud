import '../time/civil_date.dart';
import 'calendar_event.dart';
import 'calendar_overlay.dart';
import 'calendar_recurrence.dart';

/// Read-only access to mirrored calendar events (SPEC §12.1). The host layer
/// fetches + parses (CalDAV/ICS network, or the device calendar) and hands the
/// events to an implementation; `core` only reads. Recurrence is expanded here,
/// so callers see concrete instances.
abstract interface class CalendarProvider {
  /// Concrete event instances whose span intersects [date].
  List<CalendarEvent> eventsOn(CivilDate date);

  /// The dial overlay for [date] (timed arcs lane-packed, all-day separated).
  DayOverlay overlayOn(CivilDate date);
}

/// In-memory [CalendarProvider] over a fixed event list, which may include
/// recurring masters (RRULE) — they are expanded per query. This is what the
/// desktop hub wires from freshly-fetched sources, and what tests use.
class InMemoryCalendarProvider implements CalendarProvider {
  InMemoryCalendarProvider(Iterable<CalendarEvent> events)
      : _events = List.unmodifiable(events);

  final List<CalendarEvent> _events;

  @override
  List<CalendarEvent> eventsOn(CivilDate date) {
    // Widen the expansion window by a day so an overnight instance that began
    // yesterday still surfaces today; we then keep only the instances whose
    // span actually intersects [date].
    final from = date.addDays(-1);
    final instances = <CalendarEvent>[];
    for (final e in _events) {
      instances.addAll(expandRecurring(e, from: from, to: date));
    }
    return [
      for (final i in instances)
        if (_intersectsDate(i, date)) i,
    ]..sort((a, b) => a.startTs.compareTo(b.startTs));
  }

  @override
  DayOverlay overlayOn(CivilDate date) => overlayFor(date, eventsOn(date));

  /// True if [e]'s wall-clock span touches [date]. All-day is `[start, end)`
  /// exclusive on the end day; a timed event ending exactly at [date] midnight
  /// does not count as intersecting [date].
  static bool _intersectsDate(CalendarEvent e, CivilDate date) {
    final startDate = wallDate(e.startTs);
    final endDate = wallDate(e.endTs);
    if (date.isBefore(startDate)) return false;
    if (e.allDay) return date.isBefore(endDate);
    if (date.isAfter(endDate)) return false;
    if (date == endDate && wallMinute(e.endTs) == 0 && startDate != endDate) {
      return false; // ends at this day's midnight
    }
    return true;
  }
}
