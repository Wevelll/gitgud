@Timeout(Duration(minutes: 2))
library;

// Real HTTP over loopback, not a unit test: the default 30-second budget is
// tight when the whole suite runs its isolates in parallel, and a timeout here
// says nothing about the code under test.

import 'package:day_dial/data/synced_day_repository.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// End-to-end: the web client talks to a real desktop data-API server (both in
/// the same process here). Proves edits made on the "web" repository are pushed
/// to and persisted by the "desktop" repository.
void main() {
  test('web client hydrates from the hub and pushes edits back', () async {
    // The "desktop" side: an in-memory repo behind a data-API server.
    final desktop = InMemoryDayRepository(profiles: [testProfile()]);
    desktop.addHabit(label: 'Water', colorHex: '#3E7CB1', dailyTarget: 8);
    final server = DataApiServer(
      DayDialTools(desktop, const AllowAllConsent()),
    );
    final hub = await server.start();

    try {
      // The "web" side connects and mirrors the desktop state.
      final web = await SyncedDayRepository.connect(hub: hub);
      addTearDown(web.close);
      expect(web.activeProfile().name, 'Weekday');
      expect(web.habits().single.label, 'Water');

      // An edit on the web is pushed to the desktop.
      final today = CivilDate.fromDateTime(DateTime.now());
      web.incrementHabit(web.habits().single.id, date: today);

      await web.idle; // the push is awaited, not slept on

      expect(
        habitCountOn(today, desktop.habits().single.id, desktop.habitEvents()),
        1,
        reason: 'the increment should have synced to the desktop',
      );
    } finally {
      await server.close();
    }
  });

  test('sub-blocks created on the web sync to the desktop', () async {
    final desktop = InMemoryDayRepository(profiles: [testProfile()]);
    final server = DataApiServer(
      DayDialTools(desktop, const AllowAllConsent()),
    );
    final hub = await server.start();

    try {
      final web = await SyncedDayRepository.connect(hub: hub);
      addTearDown(web.close);
      // Free time is 18:00–23:00 in the reference ring.
      web.addSubBlock(
        parentId: 'free',
        name: 'Gym',
        colorHex: '#2E8B8B',
        startMin: 1080,
        endMin: 1140,
      );

      await web.idle; // the push is awaited, not slept on

      expect(
        desktop.subBlocks().of('free').single.name,
        'Gym',
        reason: 'the sub-block should have synced to the desktop',
      );
    } finally {
      await server.close();
    }
  });

  test('a burst of edits does not become a burst of hub round trips', () async {
    final desktop = InMemoryDayRepository(profiles: [testProfile()]);
    desktop.addHabit(label: 'Water', colorHex: '#3E7CB1');
    final server = DataApiServer(
      DayDialTools(desktop, const AllowAllConsent()),
    );
    final hub = await server.start();
    final client = _CountingClient();

    try {
      final web = await SyncedDayRepository.connect(hub: hub, client: client);
      addTearDown(web.close);
      final habit = web.habits().single.id;
      final today = CivilDate.fromDateTime(DateTime.now());

      // What dragging a boundary looks like: many edits in a row. Each one
      // used to fire its own PUT.
      for (var i = 0; i < 20; i++) {
        web.incrementHabit(habit, date: today);
      }
      await web.idle;

      // Coalesced on the wire, but the desktop still ends up with all 20 —
      // each push carries the whole snapshot, so dropping the intermediate
      // ones loses nothing.
      expect(client.puts, lessThan(20));
      expect(
        habitCountOn(today, desktop.habits().single.id, desktop.habitEvents()),
        20,
      );
    } finally {
      await server.close();
    }
  });

  test('an unreachable hub is recorded, not silently swallowed', () async {
    final desktop = InMemoryDayRepository(profiles: [testProfile()]);
    final server = DataApiServer(
      DayDialTools(desktop, const AllowAllConsent()),
    );
    final hub = await server.start();
    final web = await SyncedDayRepository.connect(hub: hub);
    addTearDown(web.close);
    await server.close(); // the desktop goes away

    web.addRecurringTask(
      label: 'Offline edit',
      recurrence: const DailyRecurrence(),
      colorHex: '#6FA85B',
    );
    await web.idle;

    // The edit still applied locally — that's the local-first bargain — but
    // the failure is visible rather than vanishing into an ignored future.
    expect(web.tasks().single.label, 'Offline edit');
    expect(web.lastError, isNotNull);
  });
}

/// Counts the PUTs that actually reach the wire, so a test can tell "one push
/// carrying everything" from "one push per edit".
class _CountingClient extends http.BaseClient {
  final _inner = http.Client();
  int puts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'PUT') puts++;
    return _inner.send(request);
  }
}
