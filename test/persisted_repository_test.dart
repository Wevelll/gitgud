import 'package:day_dial/data/persisted_day_repository.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The web build's local persistence (SPEC §8). The IndexedDB layer itself only
/// runs in a browser, so these tests exercise the part that holds the logic —
/// when a snapshot is written, what it contains, and what happens when the
/// write fails.
void main() {
  PersistedDayRepository repoWith(SnapshotSink sink, {DaySnapshot? restore}) {
    final cache = restore == null
        ? InMemoryDayRepository(
            profiles: [testProfile()],
            idFactory: uniqueIdFactory(seed: 'a'),
          )
        : InMemoryDayRepository.fromSnapshot(
            restore,
            idFactory: uniqueIdFactory(seed: 'b'),
          );
    return PersistedDayRepository(cache: cache, save: sink);
  }

  test(
    'an edit is persisted, and reloading the snapshot restores it',
    () async {
      final writes = <DaySnapshot>[];
      final repo = repoWith((s) async => writes.add(s));

      repo.addRecurringTask(
        label: 'Water the plants',
        recurrence: const DailyRecurrence(),
        colorHex: '#6FA85B',
      );
      await repo.idle;

      expect(writes, hasLength(1));

      // What a page reload does: rebuild from the last written snapshot.
      final reloaded = repoWith((_) async {}, restore: writes.last);
      expect(reloaded.tasks().map((t) => t.label), ['Water the plants']);
    },
  );

  test('a burst of edits coalesces into a final, complete write', () async {
    final writes = <DaySnapshot>[];
    // A save that takes a turn to finish, so edits land while one is in flight.
    final repo = repoWith((s) async {
      await Future<void>.delayed(Duration.zero);
      writes.add(s);
    });

    final habit = repo.addHabit(label: 'Water', colorHex: '#3E7CB1');
    for (var i = 0; i < 10; i++) {
      repo.incrementHabit(habit.id);
    }
    await repo.idle;

    // Coalesced: far fewer writes than the 11 edits, and the last one is
    // current — nothing is dropped, only the intermediate writes are.
    expect(writes.length, lessThan(11));
    expect(writes.last.habitEvents, hasLength(10));
  });

  test('a failing save is survivable — the day keeps working', () async {
    var fail = true;
    final repo = repoWith((_) async {
      if (fail) throw StateError('quota exceeded');
    });

    repo.addHabit(label: 'Water', colorHex: '#3E7CB1');
    await repo.idle;

    expect(repo.lastError, isA<StateError>());
    expect(repo.habits(), hasLength(1)); // the edit itself still applied

    fail = false;
    repo.incrementHabit(repo.habits().first.id);
    await repo.idle;
    expect(repo.lastError, isNull); // and it recovers
  });

  test('ids minted after a reload do not collide with restored ones', () async {
    final writes = <DaySnapshot>[];
    final first = repoWith((s) async => writes.add(s));
    first.addRecurringTask(
      label: 'Take meds',
      recurrence: const DailyRecurrence(),
      colorHex: '#3E7CB1',
    );
    await first.idle;

    // A reloaded store keeps minting ids; a plain 1,2,3 counter would restart
    // and re-issue an id the restored snapshot already holds.
    final reloaded = repoWith((s) async => writes.add(s), restore: writes.last);
    reloaded.addRecurringTask(
      label: 'Stretch',
      recurrence: const DailyRecurrence(),
      colorHex: '#6FA85B',
    );
    await reloaded.idle;

    final ids = reloaded.tasks().map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });
}
