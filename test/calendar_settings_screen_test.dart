import 'package:day_dial/calendar/calendar_service.dart';
import 'package:day_dial/screens/calendar_settings_screen.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ics =
    'BEGIN:VCALENDAR\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:e1\r\n'
    'SUMMARY:Standup\r\n'
    'DTSTART:20260707T090000Z\r\n'
    'DTEND:20260707T091500Z\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  testWidgets('adding a source registers it and pulls its events', (
    tester,
  ) async {
    final service = CalendarService(fetcher: (_) async => _ics);
    await tester.pumpWidget(
      MaterialApp(home: CalendarSettingsScreen(service: service)),
    );

    await tester.tap(find.text('Add calendar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Work');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://example.com/work.ics',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(service.sources, hasLength(1));
    expect(service.sources.single.name, 'Work');
    expect(
      service.provider.eventsOn(CivilDate.parse('2026-07-07')),
      hasLength(1),
    );
    expect(find.text('Work'), findsOneWidget); // listed in the UI
  });

  testWidgets('toggling a source off disables it', (tester) async {
    final service = CalendarService(
      sources: const [
        CalendarSource(
          id: 's1',
          kind: CalendarSourceKind.ics,
          name: 'Work',
          url: 'https://example.com/work.ics',
        ),
      ],
      fetcher: (_) async => _ics,
    );
    await tester.pumpWidget(
      MaterialApp(home: CalendarSettingsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.sources.single.enabled, isFalse);
  });
}
