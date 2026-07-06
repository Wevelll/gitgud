import 'package:day_dial/data/synced_day_repository.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_mcp/day_dial_mcp.dart';
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
      expect(web.activeProfile().name, 'Weekday');
      expect(web.habits().single.label, 'Water');

      // An edit on the web is pushed to the desktop.
      final today = CivilDate.fromDateTime(DateTime.now());
      web.incrementHabit(web.habits().single.id, date: today);

      // Give the async push a moment to land.
      await Future<void>.delayed(const Duration(milliseconds: 200));

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
      // Free time is 18:00–23:00 in the reference ring.
      web.addSubBlock(
        parentId: 'free',
        name: 'Gym',
        colorHex: '#2E8B8B',
        startMin: 1080,
        endMin: 1140,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        desktop.subBlocks().of('free').single.name,
        'Gym',
        reason: 'the sub-block should have synced to the desktop',
      );
    } finally {
      await server.close();
    }
  });
}
