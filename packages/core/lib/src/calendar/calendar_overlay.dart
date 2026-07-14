import '../time/civil_date.dart';
import '../time/day_minutes.dart';
import 'calendar_event.dart';

/// One calendar event positioned for a single day's dial (SPEC §2.5). A timed
/// event carries a minute-of-day span `[startMin, endMin)` clipped to the day
/// and a [track] (lane) so overlapping events can be drawn on concentric rings.
/// An [allDay] event has no ring span — the UI shows it in the hub, not on the
/// ring.
class OverlayEvent {
  const OverlayEvent({
    required this.eventId,
    required this.sourceId,
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.allDay,
    required this.track,
    this.calendarName,
  });

  final String eventId;

  /// The [CalendarSource] this event came from — lets the UI color it per
  /// calendar.
  final String sourceId;
  final String title;

  /// Minute-of-day start/end for the clipped span, `[0, 1440]`. `endMin` may be
  /// 1440 (the event runs to midnight). Meaningless when [allDay].
  final int startMin;
  final int endMin;
  final bool allDay;

  /// Concentric lane index for overlapping timed events (0 = innermost). Always
  /// 0 for all-day events.
  final int track;
  final String? calendarName;

  int get durationMin => endMin - startMin;

  @override
  bool operator ==(Object other) =>
      other is OverlayEvent &&
      other.eventId == eventId &&
      other.sourceId == sourceId &&
      other.title == title &&
      other.startMin == startMin &&
      other.endMin == endMin &&
      other.allDay == allDay &&
      other.track == track &&
      other.calendarName == calendarName;

  @override
  int get hashCode => Object.hash(
      eventId, sourceId, title, startMin, endMin, allDay, track, calendarName);

  @override
  String toString() => allDay
      ? 'OverlayEvent("$title", all-day)'
      : 'OverlayEvent("$title", $startMin–$endMin, track $track)';
}

/// Everything to draw for [date]: timed events (as ring arcs, lane-packed) and
/// all-day events (for the hub). [trackCount] is how many concentric lanes the
/// timed events need.
class DayOverlay {
  const DayOverlay({
    required this.date,
    required this.timed,
    required this.allDay,
    required this.trackCount,
  });

  final CivilDate date;
  final List<OverlayEvent> timed;
  final List<OverlayEvent> allDay;
  final int trackCount;

  bool get isEmpty => timed.isEmpty && allDay.isEmpty;
}

/// Builds the [DayOverlay] for [date] from already-expanded [events] (recurrence
/// expansion happens upstream). Multi-day events are clipped to [date]; an event
/// ending exactly at midnight does not spill onto the next day. Timed events are
/// lane-packed so overlaps land on separate tracks.
DayOverlay overlayFor(CivilDate date, Iterable<CalendarEvent> events) {
  final allDay = <OverlayEvent>[];
  final clipped = <OverlayEvent>[]; // track assigned later

  for (final e in events) {
    final startDate = wallDate(e.startTs);
    final endDate = wallDate(e.endTs);

    if (e.allDay) {
      // All-day span is [startDate, endDate) exclusive.
      if (!date.isBefore(startDate) && date.isBefore(endDate)) {
        allDay.add(OverlayEvent(
          eventId: e.id,
          sourceId: e.sourceId,
          title: e.title,
          startMin: 0,
          endMin: minutesPerDay,
          allDay: true,
          track: 0,
          calendarName: e.calendarName,
        ));
      }
      continue;
    }

    if (date.isBefore(startDate) || date.isAfter(endDate)) continue;
    final segStart = date == startDate ? wallMinute(e.startTs) : 0;
    final segEnd = date == endDate ? wallMinute(e.endTs) : minutesPerDay;
    if (segEnd <= segStart) continue; // zero-length or ends at this midnight
    clipped.add(OverlayEvent(
      eventId: e.id,
      sourceId: e.sourceId,
      title: e.title,
      startMin: segStart,
      endMin: segEnd,
      allDay: false,
      track: 0,
      calendarName: e.calendarName,
    ));
  }

  final timed = _assignTracks(clipped);
  final trackCount = timed.isEmpty
      ? 0
      : timed.map((e) => e.track).reduce((a, b) => a > b ? a : b) + 1;
  return DayOverlay(
      date: date, timed: timed, allDay: allDay, trackCount: trackCount);
}

/// Greedy interval lane-packing: sort by start (then end), place each event on
/// the first lane whose last event has ended by its start. Returns events with
/// [OverlayEvent.track] filled in, in start order.
List<OverlayEvent> _assignTracks(List<OverlayEvent> events) {
  final sorted = [...events]..sort((a, b) {
      final c = a.startMin.compareTo(b.startMin);
      return c != 0 ? c : a.endMin.compareTo(b.endMin);
    });
  final laneEnds = <int>[]; // laneEnds[i] = end minute of last event on lane i
  final out = <OverlayEvent>[];
  for (final e in sorted) {
    var lane = laneEnds.indexWhere((end) => end <= e.startMin);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(e.endMin);
    } else {
      laneEnds[lane] = e.endMin;
    }
    out.add(OverlayEvent(
      eventId: e.eventId,
      sourceId: e.sourceId,
      title: e.title,
      startMin: e.startMin,
      endMin: e.endMin,
      allDay: false,
      track: lane,
      calendarName: e.calendarName,
    ));
  }
  return out;
}
