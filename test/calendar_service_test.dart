import 'package:day_dial/calendar/calendar_service.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _ics = 'BEGIN:VCALENDAR\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:lunch\r\n'
    'SUMMARY:Lunch\r\n'
    'DTSTART:20260707T120000Z\r\n'
    'DTEND:20260707T130000Z\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  CalendarSource src(String id, {bool enabled = true}) => CalendarSource(
        id: id,
        kind: CalendarSourceKind.ics,
        name: id,
        url: 'https://example.com/$id.ics',
        colorHex: '#AABBCC',
        enabled: enabled,
      );

  test('refresh parses fetched ICS into the provider', () async {
    final service = CalendarService(
      sources: [src('work')],
      fetcher: (_) async => _ics,
    );
    final failed = await service.refresh();
    expect(failed, isEmpty);

    final events = service.provider.eventsOn(CivilDate.parse('2026-07-07'));
    expect(events, hasLength(1));
    expect(events.single.title, 'Lunch');
    expect(events.single.sourceId, 'work');
  });

  test('a failing source is skipped, not fatal', () async {
    final service = CalendarService(
      sources: [src('good'), src('bad')],
      fetcher: (s) async {
        if (s.id == 'bad') throw Exception('boom');
        return _ics;
      },
    );
    final failed = await service.refresh();
    expect(failed, ['bad']);
    // The good source still made it through.
    expect(service.provider.eventsOn(CivilDate.parse('2026-07-07')), hasLength(1));
  });

  test('disabled sources are not fetched', () async {
    var calls = 0;
    final service = CalendarService(
      sources: [src('off', enabled: false)],
      fetcher: (_) async {
        calls++;
        return _ics;
      },
    );
    await service.refresh();
    expect(calls, 0);
  });

  test('colorForSource returns the source color, else a default', () {
    final service = CalendarService(sources: [src('work')]);
    expect(service.colorForSource('work'), '#AABBCC');
    expect(service.colorForSource('unknown'), '#7C7CA8');
  });

  test('device sources yield no events on this seam', () async {
    final service = CalendarService(
      sources: [
        const CalendarSource(
          id: 'phone',
          kind: CalendarSourceKind.device,
          name: 'Phone',
          calId: 'primary',
        ),
      ],
      fetcher: (_) async => _ics,
    );
    await service.refresh();
    expect(service.provider.eventsOn(CivilDate.parse('2026-07-07')), isEmpty);
  });
}
