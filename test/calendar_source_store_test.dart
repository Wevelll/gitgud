import 'dart:io';

import 'package:day_dial/calendar/calendar_service.dart';
import 'package:day_dial/calendar/source_store.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = CalendarSource(
    id: 'a',
    kind: CalendarSourceKind.ics,
    name: 'Work',
    url: 'https://example.com/work.ics',
    colorHex: '#123456',
  );

  test('io store round-trips the source list through JSON', () async {
    final dir = Directory.systemTemp.createTempSync('daydial_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = createCalendarSourceStore(path: '${dir.path}/sources.json');

    expect(await store.load(), isEmpty); // nothing yet
    await store.save([source]);
    expect(await store.load(), [source]); // CalendarSource has value equality
  });

  test('service persists added sources; loadSources restores them', () async {
    final dir = Directory.systemTemp.createTempSync('daydial_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/sources.json';

    final first = CalendarService(
      fetcher: (_) async => '',
      store: createCalendarSourceStore(path: path),
    );
    first.addSource(source);
    await first.persist();

    final second = CalendarService(
      fetcher: (_) async => '',
      store: createCalendarSourceStore(path: path),
    );
    await second.loadSources();
    expect(second.sources, [source]);
  });

  test('a missing file loads as an empty list, not an error', () async {
    final store = createCalendarSourceStore(
      path: '${Directory.systemTemp.path}/daydial_nope_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    expect(await store.load(), isEmpty);
  });
}
