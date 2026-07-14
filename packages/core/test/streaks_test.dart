import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final today = CivilDate.parse('2026-07-07'); // a Tuesday

  RecurringTask task(String id, Recurrence rule) => RecurringTask(
        id: id,
        label: id,
        colorHex: '#fff',
        recurrence: rule,
        createdAt: '2026-01-01T00:00:00Z',
      );

  TaskCompletion done(String taskId, CivilDate date) => TaskCompletion(
        id: '$taskId@${date.iso}',
        taskId: taskId,
        date: date,
        completedAt: '${date.iso}T09:00:00Z',
      );

  Habit habit(String id,
          {HabitPolarity polarity = HabitPolarity.good, int? target}) =>
      Habit(
        id: id,
        label: id,
        colorHex: '#fff',
        createdAt: '2026-01-01T00:00:00Z',
        polarity: polarity,
        dailyTarget: target,
      );

  HabitEvent ev(String habitId, CivilDate date) => HabitEvent(
      id: '$habitId@${date.iso}',
      habitId: habitId,
      date: date,
      ts: '${date.iso}T10:00:00Z');

  group('taskStreak (daily)', () {
    final t = task('meds', const DailyRecurrence());

    test('counts consecutive completed days back from today', () {
      final completions = [
        for (var i = 0; i < 4; i++) done('meds', today.addDays(-i)),
      ];
      expect(taskStreak(t, completions, asOf: today),
          const StreakInfo(current: 4, longest: 4));
    });

    test('an incomplete today does not break the streak (grace)', () {
      final completions = [
        for (var i = 1; i <= 3; i++) done('meds', today.addDays(-i)),
      ]; // today missing
      expect(taskStreak(t, completions, asOf: today).current, 3);
    });

    test('a missed earlier day breaks the current streak', () {
      final completions = [
        done('meds', today),
        done('meds', today.addDays(-1)),
        // gap at -2
        done('meds', today.addDays(-3)),
        done('meds', today.addDays(-4)),
      ];
      final s = taskStreak(t, completions, asOf: today);
      expect(s.current, 2);
      expect(s.longest, 2);
    });
  });

  group('taskStreak (weekly)', () {
    // Due Tue/Thu only; off-days must not break the streak.
    final t = task('gym', WeeklyRecurrence({2, 4}));

    test('off-days are skipped, not counted as breaks', () {
      // today is Tue 2026-07-07. Prior due days: Thu 07-02, Tue 06-30, ...
      final completions = [
        done('gym', today), // Tue 07-07
        done('gym', CivilDate.parse('2026-07-02')), // Thu
        done('gym', CivilDate.parse('2026-06-30')), // Tue
      ];
      final s = taskStreak(t, completions, asOf: today);
      expect(s.current, 3);
    });

    test('a missed due day breaks it even with grace on today', () {
      final completions = [
        // today (Tue) not done -> grace
        // Thu 07-02 not done -> break
        done('gym', CivilDate.parse('2026-06-30')),
      ];
      expect(taskStreak(t, completions, asOf: today).current, 0);
    });
  });

  group('habitDaySucceeded', () {
    test('good with target needs count >= target', () {
      final h = habit('water', target: 8);
      expect(habitDaySucceeded(h, 8), isTrue);
      expect(habitDaySucceeded(h, 7), isFalse);
    });

    test('good without target needs at least one', () {
      final h = habit('read');
      expect(habitDaySucceeded(h, 1), isTrue);
      expect(habitDaySucceeded(h, 0), isFalse);
    });

    test('bad with cap needs count <= cap', () {
      final h = habit('smoke', polarity: HabitPolarity.bad, target: 3);
      expect(habitDaySucceeded(h, 3), isTrue);
      expect(habitDaySucceeded(h, 4), isFalse);
    });

    test('bad without cap needs a clean zero', () {
      final h = habit('junk', polarity: HabitPolarity.bad);
      expect(habitDaySucceeded(h, 0), isTrue);
      expect(habitDaySucceeded(h, 1), isFalse);
    });
  });

  group('habitStreak', () {
    test('good habit counts days meeting the target', () {
      final h = habit('water', target: 2);
      final events = [
        for (var i = 0; i < 3; i++) ...[
          ev('water', today.addDays(-i)),
          ev('water', today.addDays(-i)),
        ],
      ]; // 2/day for 3 days
      expect(habitStreak(h, events, asOf: today).current, 3);
    });

    test('bad habit: a clean run, broken by a slip', () {
      final h = habit('smoke', polarity: HabitPolarity.bad);
      final events = [
        ev('smoke', today.addDays(-2)), // slip 2 days ago
      ];
      // today clean, yesterday clean, -2 slipped
      final s = habitStreak(h, events, asOf: today);
      expect(s.current, 2);
    });

    test('longest captures the best past run independent of current', () {
      final h = habit('read');
      final events = [
        // a 3-day run then a gap then today
        ev('read', today.addDays(-5)),
        ev('read', today.addDays(-4)),
        ev('read', today.addDays(-3)),
        ev('read', today),
      ];
      final s = habitStreak(h, events, asOf: today);
      expect(s.longest, 3);
      expect(s.current, 1);
    });
  });
}
