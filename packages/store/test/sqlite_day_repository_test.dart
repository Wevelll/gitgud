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

  group('profiles: multi-template + weekday resolution (persisted)', () {
    test('add, assign weekdays, and resolve by date', () {
      final repo = memRepo(); // seeds weekday()
      repo.addProfile(weekend());
      repo.setProfileWeekdays('weekday', 31); // Mon–Fri
      repo.setProfileWeekdays('weekend', 96); // Sat–Sun
      expect(repo.profileForDate(CivilDate.parse('2026-07-06')).id, 'weekday');
      expect(repo.profileForDate(CivilDate.parse('2026-07-11')).id, 'weekend');
      repo.close();
    });

    test('setDefaultProfile and remove a non-active profile', () {
      final repo = memRepo(seed: [weekday(), weekend()]);
      repo.setDefaultProfile('weekend');
      expect(
        repo.profiles().firstWhere((p) => p.id == 'weekend').isDefault,
        isTrue,
      );
      repo.removeProfile('weekend'); // weekday is active, so this is allowed
      expect(repo.profiles().map((p) => p.id), ['weekday']);
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

      repo.uncompleteTask(task.id, date); // un-check
      expect(repo.completions(), isEmpty);
      repo.close();
    });

    test('update, archive, and delete a task persist', () {
      final repo = memRepo();
      final date = CivilDate.parse('2026-07-03');
      final task = repo.addRecurringTask(
        label: 'Meds',
        recurrence: const DailyRecurrence(),
        colorHex: '#6FA85B',
      );

      // Edit label + recurrence; re-read from the db.
      repo.updateRecurringTask(
        task.id,
        label: 'Take meds',
        recurrence: WeeklyRecurrence({1, 5}),
      );
      final reread = repo.tasks().single;
      expect(reread.label, 'Take meds');
      expect(reread.recurrence, WeeklyRecurrence({1, 5}));

      // Archive keeps the row but drops it from the tray.
      repo.setTaskArchived(task.id, archived: true);
      expect(trayFor(date, repo.tasks(), repo.completions()), isEmpty);
      expect(repo.tasks().single.archived, isTrue);
      repo.setTaskArchived(task.id, archived: false);

      // Delete cascades the completions (task_completions ON DELETE CASCADE).
      repo.completeTask(task.id, date);
      expect(repo.completions(), hasLength(1));
      repo.deleteRecurringTask(task.id);
      expect(repo.tasks(), isEmpty);
      expect(repo.completions(), isEmpty);
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

  group('sub-blocks persist', () {
    test('add, update, delete, and clip on parent resize', () {
      final repo = memRepo();
      // Work is 09:00–23:00 in the weekday ring. Add a 10:00–11:00 sub-block.
      final gym = repo.addSubBlock(
        parentId: 'work',
        name: 'Gym',
        colorHex: '#abc',
        startMin: 600,
        endMin: 660,
      );
      expect(repo.subBlocks().of('work').single.name, 'Gym');

      repo.updateSubBlock(gym.id, name: 'Yoga', endMin: 690); // 10:00–11:30
      final afterEdit = repo.subBlocks().of('work').single;
      expect(afterEdit.name, 'Yoga');
      expect(afterEdit.endMin, 690);

      // Move Work's start 09:00 → 11:00; the 10:00–11:30 block clips to 11:00.
      repo.updateBlock('work', startMin: 660);
      final clipped = repo.subBlocks().of('work').single;
      expect(clipped.startMin, 660);
      expect(clipped.endMin, 690);

      repo.deleteSubBlock(clipped.id);
      expect(repo.subBlocks().of('work'), isEmpty);
      repo.close();
    });

    test('sub-blocks survive a real reopen (file-backed)', () {
      final dir = Directory.systemTemp.createTempSync('daydial_sub');
      try {
        final path = '${dir.path}/day.db';
        final repo = SqliteDayRepository.open(
          path: path,
          seedIfEmpty: [weekday()],
          idFactory: () => 'sb',
          clock: fixedClock,
        );
        repo.addSubBlock(
          parentId: 'work',
          name: 'Gym',
          colorHex: '#abc',
          startMin: 600,
          endMin: 660,
        );
        repo.close();

        final reopened = SqliteDayRepository.open(path: path);
        expect(reopened.subBlocks().of('work').single.name, 'Gym');
        reopened.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('habits', () {
    test('add, increment, count, and decrement (persisted)', () {
      final repo = memRepo();
      final today = CivilDate.parse('2026-07-03');
      final water =
          repo.addHabit(label: 'Water', colorHex: '#3E7CB1', dailyTarget: 8);

      repo.incrementHabit(water.id, date: today);
      repo.incrementHabit(water.id, date: today);
      expect(habitCountOn(today, water.id, repo.habitEvents()), 2);

      expect(repo.decrementHabit(water.id, today), isTrue);
      expect(habitCountOn(today, water.id, repo.habitEvents()), 1);

      // Can't go below the recorded events.
      expect(repo.decrementHabit(water.id, today), isTrue);
      expect(repo.decrementHabit(water.id, today), isFalse);

      final summary = habitCountsFor(today, repo.habits(), repo.habitEvents());
      expect(summary.single.target, 8);
      repo.close();
    });

    test('incrementing an unknown habit throws', () {
      final repo = memRepo();
      expect(() => repo.incrementHabit('nope'), throwsStateError);
      repo.close();
    });
  });

  test('restore replaces all state from a snapshot (persisted)', () {
    final source = memRepo();
    final today = CivilDate.parse('2026-07-03');
    source.addHabit(label: 'Water', colorHex: '#3E7CB1', dailyTarget: 8);
    source.addRecurringTask(
        label: 'Meds', recurrence: const DailyRecurrence(), colorHex: '#abc');
    final snap = source.snapshot();

    final target = memRepo(seed: [weekend()]);
    expect(target.habits(), isEmpty);
    target.restore(snap);

    expect(target.activeProfile().name, 'Weekday');
    expect(target.habits().single.label, 'Water');
    expect(target.tasks().single.label, 'Meds');
    expect(habitCountOn(today, target.habits().single.id, target.habitEvents()),
        0);
    source.close();
    target.close();
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
