import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  CalendarEvent ev({
    required String id,
    required String start,
    required String end,
    String title = 'Event',
    bool allDay = false,
    String? rrule,
  }) =>
      CalendarEvent(
        id: id,
        sourceId: 'src',
        uid: id,
        title: title,
        startTs: start,
        endTs: end,
        allDay: allDay,
        rrule: rrule,
      );

  group('CalendarEvent', () {
    test('duration and json round-trip', () {
      final e =
          ev(id: '1', start: '2026-07-07T09:00:00', end: '2026-07-07T10:30:00');
      expect(e.durationMin, 90);
      expect(CalendarEvent.fromJson(e.toJson()), e);
    });

    test('rejects end before start', () {
      expect(
        () => ev(
            id: '1', start: '2026-07-07T10:00:00', end: '2026-07-07T09:00:00'),
        throwsArgumentError,
      );
    });

    test('wallDate/wallMinute read the timestamp wall clock', () {
      expect(wallDate('2026-07-07T14:30:00'), CivilDate.parse('2026-07-07'));
      expect(wallMinute('2026-07-07T14:30:00'), 14 * 60 + 30);
      expect(wallMinute('2026-07-07'), 0);
    });
  });

  group('icsToEvents', () {
    test('parses a timed VEVENT with escaped summary', () {
      const ics = 'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:abc-123\r\n'
          'SUMMARY:Lunch\\, with team\r\n'
          'DTSTART:20260707T120000Z\r\n'
          'DTEND:20260707T130000Z\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      final events = icsToEvents(ics, sourceId: 'work');
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.title, 'Lunch, with team');
      expect(e.uid, 'abc-123');
      expect(e.startTs, '2026-07-07T12:00:00Z');
      expect(e.endTs, '2026-07-07T13:00:00Z');
      expect(e.allDay, isFalse);
    });

    test('parses an all-day VEVENT (VALUE=DATE)', () {
      const ics = 'BEGIN:VEVENT\r\n'
          'UID:holiday\r\n'
          'SUMMARY:Holiday\r\n'
          'DTSTART;VALUE=DATE:20260707\r\n'
          'DTEND;VALUE=DATE:20260708\r\n'
          'END:VEVENT\r\n';
      final e = icsToEvents(ics, sourceId: 's').single;
      expect(e.allDay, isTrue);
      expect(e.startTs, '2026-07-07T00:00:00');
      expect(e.endTs, '2026-07-08T00:00:00');
    });

    test('unfolds continuation lines', () {
      const ics = 'BEGIN:VEVENT\r\n'
          'UID:x\r\n'
          'SUMMARY:A very long \r\n title here\r\n'
          'DTSTART:20260707T090000Z\r\n'
          'DTEND:20260707T100000Z\r\n'
          'END:VEVENT\r\n';
      expect(icsToEvents(ics, sourceId: 's').single.title,
          'A very long title here');
    });

    test('captures RRULE', () {
      const ics = 'BEGIN:VEVENT\r\n'
          'UID:standup\r\n'
          'SUMMARY:Standup\r\n'
          'DTSTART:20260706T090000Z\r\n'
          'DTEND:20260706T091500Z\r\n'
          'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r\n'
          'END:VEVENT\r\n';
      expect(icsToEvents(ics, sourceId: 's').single.rrule,
          'FREQ=WEEKLY;BYDAY=MO,WE,FR');
    });
  });

  group('expandRecurring', () {
    test('daily with count', () {
      final e = ev(
        id: 'd',
        start: '2026-07-07T08:00:00',
        end: '2026-07-07T08:30:00',
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      final out = expandRecurring(e,
          from: CivilDate.parse('2026-07-01'),
          to: CivilDate.parse('2026-07-31'));
      expect(out.map((x) => x.startTs), [
        '2026-07-07T08:00:00',
        '2026-07-08T08:00:00',
        '2026-07-09T08:00:00',
      ]);
      expect(out.every((x) => x.rrule == null), isTrue);
    });

    test('weekly BYDAY within a window', () {
      // Master Monday 2026-07-06.
      final e = ev(
        id: 'w',
        start: '2026-07-06T09:00:00',
        end: '2026-07-06T09:15:00',
        rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
      );
      final out = expandRecurring(e,
          from: CivilDate.parse('2026-07-06'),
          to: CivilDate.parse('2026-07-12'));
      expect(out.map((x) => x.startTs.substring(0, 10)),
          ['2026-07-06', '2026-07-08']); // Mon, Wed
    });

    test('weekly INTERVAL=2 skips the off week', () {
      final e = ev(
        id: 'w2',
        start: '2026-07-06T09:00:00',
        end: '2026-07-06T09:15:00',
        rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO',
      );
      final out = expandRecurring(e,
          from: CivilDate.parse('2026-07-01'),
          to: CivilDate.parse('2026-07-31'));
      expect(out.map((x) => x.startTs.substring(0, 10)),
          ['2026-07-06', '2026-07-20']); // skip 07-13
    });

    test('UNTIL bounds the series', () {
      final e = ev(
        id: 'u',
        start: '2026-07-07T08:00:00',
        end: '2026-07-07T08:30:00',
        rrule: 'FREQ=DAILY;UNTIL=20260709T000000Z',
      );
      final out = expandRecurring(e,
          from: CivilDate.parse('2026-07-01'),
          to: CivilDate.parse('2026-07-31'));
      expect(out.map((x) => x.startTs.substring(0, 10)), [
        '2026-07-07',
        '2026-07-08'
      ]); // 07-09 excluded (after UNTIL midnight)
    });

    test('monthly by day-of-month', () {
      final e = ev(
        id: 'm',
        start: '2026-01-15T10:00:00',
        end: '2026-01-15T11:00:00',
        rrule: 'FREQ=MONTHLY;COUNT=3',
      );
      final out = expandRecurring(e,
          from: CivilDate.parse('2026-01-01'),
          to: CivilDate.parse('2026-12-31'));
      expect(out.map((x) => x.startTs.substring(0, 10)),
          ['2026-01-15', '2026-02-15', '2026-03-15']);
    });

    test('a non-recurring event survives if it intersects the window', () {
      final e = ev(
          id: 'once', start: '2026-07-07T09:00:00', end: '2026-07-07T10:00:00');
      expect(
          expandRecurring(e,
                  from: CivilDate.parse('2026-07-07'),
                  to: CivilDate.parse('2026-07-07'))
              .single,
          e);
      expect(
          expandRecurring(e,
              from: CivilDate.parse('2026-08-01'),
              to: CivilDate.parse('2026-08-02')),
          isEmpty);
    });
  });

  group('overlayFor', () {
    final date = CivilDate.parse('2026-07-07');

    test('timed events are clipped and lane-packed on overlap', () {
      final events = [
        ev(id: 'a', start: '2026-07-07T09:00:00', end: '2026-07-07T10:00:00'),
        ev(id: 'b', start: '2026-07-07T09:30:00', end: '2026-07-07T10:30:00'),
        ev(id: 'c', start: '2026-07-07T11:00:00', end: '2026-07-07T12:00:00'),
      ];
      final o = overlayFor(date, events);
      expect(o.allDay, isEmpty);
      expect(o.timed, hasLength(3));
      // a and b overlap -> different tracks; c reuses track 0.
      final byId = {for (final e in o.timed) e.eventId: e};
      expect(byId['a']!.track, 0);
      expect(byId['b']!.track, 1);
      expect(byId['c']!.track, 0);
      expect(o.trackCount, 2);
    });

    test('an overnight event is clipped to each day', () {
      final e =
          ev(id: 'n', start: '2026-07-07T23:00:00', end: '2026-07-08T01:00:00');
      final today = overlayFor(date, [e]).timed.single;
      expect(today.startMin, 23 * 60);
      expect(today.endMin, 1440);
      final tomorrow =
          overlayFor(CivilDate.parse('2026-07-08'), [e]).timed.single;
      expect(tomorrow.startMin, 0);
      expect(tomorrow.endMin, 60);
    });

    test('an event ending exactly at midnight does not spill', () {
      final e =
          ev(id: 'm', start: '2026-07-07T22:00:00', end: '2026-07-08T00:00:00');
      expect(overlayFor(CivilDate.parse('2026-07-08'), [e]).timed, isEmpty);
      expect(overlayFor(date, [e]).timed.single.endMin, 1440);
    });

    test('all-day events go to the all-day list, not the ring', () {
      final e = ev(
          id: 'h',
          start: '2026-07-07T00:00:00',
          end: '2026-07-08T00:00:00',
          allDay: true);
      final o = overlayFor(date, [e]);
      expect(o.timed, isEmpty);
      expect(o.allDay.single.title, 'Event');
    });
  });

  group('InMemoryCalendarProvider', () {
    test('eventsOn expands recurrence and filters to the day', () {
      final master = ev(
        id: 'standup',
        start: '2026-07-06T09:00:00',
        end: '2026-07-06T09:15:00',
        title: 'Standup',
        rrule: 'FREQ=DAILY',
      );
      final provider = InMemoryCalendarProvider([master]);
      final wed = provider.eventsOn(CivilDate.parse('2026-07-08'));
      expect(wed, hasLength(1));
      expect(wed.single.startTs, '2026-07-08T09:00:00');
      expect(provider.overlayOn(CivilDate.parse('2026-07-08')).timed,
          hasLength(1));
    });

    test('an overnight instance surfaces on the following day', () {
      final e =
          ev(id: 'n', start: '2026-07-07T23:00:00', end: '2026-07-08T01:00:00');
      final provider = InMemoryCalendarProvider([e]);
      expect(provider.eventsOn(CivilDate.parse('2026-07-08')), hasLength(1));
    });
  });
}
