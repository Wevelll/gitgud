import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final fri = CivilDate.parse('2026-07-03');
  final sat = fri.addDays(1);

  RecurringTask task(String id, Recurrence r, {bool archived = false}) =>
      RecurringTask(
        id: id,
        label: id,
        colorHex: '#fff',
        recurrence: r,
        createdAt: '2026-07-01T08:00:00Z',
        archived: archived,
      );

  test('isDueOn respects rule and archived flag', () {
    final t = task('meds', const DailyRecurrence());
    expect(t.isDueOn(fri), isTrue);
    expect(t.copyWith(archived: true).isDueOn(fri), isFalse);
  });

  group('trayFor', () {
    test('includes due tasks and marks completed ones', () {
      final tasks = [
        task('meds', const DailyRecurrence()),
        task('stretch', WeeklyRecurrence({5})), // Fri only
        task('weekend', WeeklyRecurrence({6, 7})), // Sat/Sun
        task('old', const DailyRecurrence(), archived: true),
      ];
      final completions = [
        TaskCompletion(
          id: 'c1',
          taskId: 'meds',
          date: fri,
          completedAt: '2026-07-03T09:00:00Z',
        ),
        // A completion on the wrong date must not count.
        TaskCompletion(
          id: 'c2',
          taskId: 'stretch',
          date: sat,
          completedAt: '2026-07-04T09:00:00Z',
        ),
      ];

      final tray = trayFor(fri, tasks, completions);
      final byId = {for (final i in tray) i.task.id: i.doneToday};

      expect(byId.keys, containsAll(['meds', 'stretch']));
      expect(byId.containsKey('weekend'), isFalse); // not due Friday
      expect(byId.containsKey('old'), isFalse); // archived
      expect(byId['meds'], isTrue); // completed today
      expect(byId['stretch'], isFalse); // completion was for Saturday
    });
  });
}
