import 'dart:convert';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

DayProfile weekday() => DayProfile.ring(
      id: 'weekday',
      name: 'Weekday',
      isDefault: true,
      segmentIds: const ['sleep', 'work'],
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
        (startMin: 420, name: 'Work', colorHex: '#3E7CB1'),
      ],
    );

/// A repository populated with one of everything, for round-trip coverage.
InMemoryDayRepository populated() {
  final repo = InMemoryDayRepository(profiles: [weekday()]);
  final task = repo.addRecurringTask(
      label: 'Meds', recurrence: WeeklyRecurrence({1, 3, 5}), colorHex: '#abc');
  repo.completeTask(task.id, CivilDate.parse('2026-07-03'));
  repo.logActual(
      category: 'Work',
      startTs: '2026-07-03T09:00:00Z',
      endTs: '2026-07-03T10:30:00Z',
      source: LogSource.agent);
  final habit = repo.addHabit(
      label: 'Water',
      colorHex: '#3E7CB1',
      polarity: HabitPolarity.good,
      dailyTarget: 8);
  repo.incrementHabit(habit.id, date: CivilDate.parse('2026-07-03'));
  return repo;
}

void main() {
  test('snapshot captures the whole state', () {
    final snap = populated().snapshot();
    expect(snap.activeProfileId, 'weekday');
    expect(snap.profiles, hasLength(1));
    expect(snap.tasks, hasLength(1));
    expect(snap.completions, hasLength(1));
    expect(snap.logs, hasLength(1));
    expect(snap.habits, hasLength(1));
    expect(snap.habitEvents, hasLength(1));
  });

  test('JSON round-trips losslessly (through a string, as over the wire)', () {
    final original = populated().snapshot();
    final wire = jsonEncode(original.toJson());
    final restored =
        DaySnapshot.fromJson((jsonDecode(wire) as Map).cast<String, Object?>());

    // Rehydrate into a repository and compare observable state.
    final repo = InMemoryDayRepository.fromSnapshot(restored);
    final date = CivilDate.parse('2026-07-03');

    expect(repo.activeProfile().name, 'Weekday');
    expect(repo.activeProfile().segments.first.wrapsMidnight, isTrue);
    expect(repo.tasks().single.recurrence, WeeklyRecurrence({1, 3, 5}));
    expect(repo.completions().single.date, date);
    expect(repo.logs().single.source, LogSource.agent);
    expect(repo.logs().single.durationMin, 90);
    expect(repo.habits().single.dailyTarget, 8);
    expect(habitCountOn(date, repo.habits().single.id, repo.habitEvents()), 1);
  });

  test('rehydrated repository is fully functional (can be edited)', () {
    final snap = populated().snapshot();
    final repo = InMemoryDayRepository.fromSnapshot(snap);
    // Ring edits still work on the restored profile.
    repo.addBlock(name: 'Lunch', colorHex: '#000', startMin: 720, endMin: 780);
    expect(repo.activeProfile().segments.any((s) => s.name == 'Lunch'), isTrue);
  });
}
