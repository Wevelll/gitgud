import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final today = CivilDate.parse('2026-07-03');
  final yesterday = today.addDays(-1);

  Habit habit(String id,
          {HabitPolarity polarity = HabitPolarity.good,
          int? target,
          bool archived = false}) =>
      Habit(
        id: id,
        label: id,
        colorHex: '#fff',
        createdAt: '2026-07-01T00:00:00Z',
        polarity: polarity,
        dailyTarget: target,
        archived: archived,
      );

  HabitEvent ev(String id, String habitId, CivilDate date) => HabitEvent(
      id: id, habitId: habitId, date: date, ts: '${date.iso}T10:00:00Z');

  test('habitCountOn tallies only that habit on that date', () {
    final events = [
      ev('1', 'water', today),
      ev('2', 'water', today),
      ev('3', 'water', yesterday), // different day
      ev('4', 'smoke', today), // different habit
    ];
    expect(habitCountOn(today, 'water', events), 2);
    expect(habitCountOn(yesterday, 'water', events), 1);
    expect(habitCountOn(today, 'nope', events), 0);
  });

  group('habitCountsFor', () {
    test('includes every active habit with its count, zeros included', () {
      final habits = [
        habit('water', target: 8),
        habit('smoke', polarity: HabitPolarity.bad)
      ];
      final events = [ev('1', 'water', today), ev('2', 'water', today)];

      final day = habitCountsFor(today, habits, events);
      final byId = {for (final d in day) d.habit.id: d};

      expect(byId['water']!.count, 2);
      expect(byId['smoke']!.count, 0); // no presses today
    });

    test('excludes archived habits', () {
      final habits = [habit('old', archived: true), habit('water')];
      final day = habitCountsFor(today, habits, const []);
      expect(day.map((d) => d.habit.id), ['water']);
    });

    test('targetReached reflects the daily target', () {
      final habits = [habit('water', target: 3)];
      final twoEvents = [ev('1', 'water', today), ev('2', 'water', today)];
      final threeEvents = [...twoEvents, ev('3', 'water', today)];

      expect(habitCountsFor(today, habits, twoEvents).single.targetReached,
          isFalse);
      expect(habitCountsFor(today, habits, threeEvents).single.targetReached,
          isTrue);
    });

    test('no target means targetReached is false', () {
      final day = habitCountsFor(today, [habit('smoke')], const []);
      expect(day.single.target, isNull);
      expect(day.single.targetReached, isFalse);
    });
  });
}
