import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_store/day_dial_store.dart';
import 'package:test/test.dart';

DayProfile weekday() => DayProfile.ring(
      id: 'weekday',
      name: 'Weekday',
      isDefault: true,
      segmentIds: const ['sleep', 'morning', 'work'],
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
        (startMin: 420, name: 'Morning', colorHex: '#C98A3E'),
        (startMin: 540, name: 'Work', colorHex: '#3E7CB1'),
      ],
    );

DayProfile weekend() => DayProfile.ring(
      id: 'weekend',
      name: 'Weekend',
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
        (startMin: 540, name: 'Chill', colorHex: '#6FA85B'),
      ],
    );

DateTime fixedClock() => DateTime(2026, 7, 3, 7, 30);

/// A deterministic in-memory repo seeded with the weekday profile.
SqliteDayRepository memRepo({List<DayProfile>? seed}) {
  var n = 0;
  return SqliteDayRepository.open(
    seedIfEmpty: seed ?? [weekday()],
    idFactory: () => 't${++n}',
    clock: fixedClock,
  );
}

void main() {
  group('seeding & profiles', () {
    test('seeds an empty db and exposes the active profile', () {
      final repo = memRepo();
      expect(repo.activeProfile().name, 'Weekday');
      expect(repo.activeProfile().segments.length, 3);
      repo.close();
    });

    test('does not reseed when profiles already exist', () {
      final repo = memRepo(seed: [weekday(), weekend()]);
      expect(repo.profiles().length, 2);
      repo.close();
    });

    test('switchProfile persists the active id', () {
      final repo = memRepo(seed: [weekday(), weekend()]);
      repo.switchProfile('weekend');
      expect(repo.activeProfile().name, 'Weekend');
      repo.close();
    });
  });

  group('block edits persist', () {
    test('addBlock is written and reloads through core validation', () {
      final repo = memRepo();
      final seg = repo.addBlock(
          name: 'Gym', colorHex: '#fff', startMin: 600, endMin: 660);
      // Re-read from the db to prove it round-tripped.
      final reloaded = repo.activeProfile();
      expect(reloaded.segments.any((s) => s.id == seg.id), isTrue);
      expect(reloaded.segments.fold<int>(0, (a, s) => a + s.durationMin), 1440);
      repo.close();
    });

    test('deleteBlock persists', () {
      final repo = memRepo();
      repo.deleteBlock('morning');
      expect(
          repo.activeProfile().segments.any((s) => s.id == 'morning'), isFalse);
      repo.close();
    });
  });

  group('tasks, completions, logs persist', () {
    test('recurring task + idempotent completion', () {
      final repo = memRepo();
      final task = repo.addRecurringTask(
          label: 'Meds',
          recurrence: const DailyRecurrence(),
          colorHex: '#6FA85B');
      final date = CivilDate.parse('2026-07-03');

      repo.completeTask(task.id, date);
      repo.completeTask(task.id, date); // idempotent per (task, date)
      expect(repo.completions().length, 1);

      final tray = trayFor(date, repo.tasks(), repo.completions());
      expect(tray.single.doneToday, isTrue);
      repo.close();
    });

    test('logs feed plan-vs-actual over loaded data', () {
      final repo = memRepo();
      repo.logActual(
        category: 'Work',
        startTs: '2026-07-03T14:00:00Z',
        endTs: '2026-07-03T16:00:00Z',
        source: LogSource.agent,
      );
      final date = CivilDate.parse('2026-07-03');
      final variance = planVsActual(
        dates: [date],
        profileForDate: (_) => repo.activeProfile(),
        logs: repo.logs(),
      );
      final work = variance.firstWhere((v) => v.category == 'Work');
      expect(work.actualMin, 120);
      expect(repo.logs().single.source, LogSource.agent); // enum round-trips
      repo.close();
    });
  });

  group('durability across a real reopen (file-backed)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('daydial_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('state written by one instance is read by a fresh one', () {
      final path = '${dir.path}/day.db';

      final repo = SqliteDayRepository.open(
        path: path,
        seedIfEmpty: [weekday()],
        idFactory: () => 'gym',
        clock: fixedClock,
      );
      repo.addBlock(name: 'Gym', colorHex: '#fff', startMin: 600, endMin: 660);
      repo.addRecurringTask(
          label: 'Meds',
          recurrence: const DailyRecurrence(),
          colorHex: '#6FA85B');
      repo.close();

      // Simulate a restart: brand-new connection, no seed.
      final reopened = SqliteDayRepository.open(path: path);
      expect(reopened.activeProfile().segments.any((s) => s.name == 'Gym'),
          isTrue);
      expect(reopened.tasks().single.label, 'Meds');
      expect(reopened.activeProfile().name, 'Weekday'); // active id persisted
      reopened.close();
    });
  });
}
