import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  DayProfile profile() => DayProfile.ring(
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

  InMemoryDayRepository repo() => InMemoryDayRepository(profiles: [profile()]);

  final today = CivilDate.parse('2026-07-03');

  group('recurring task lifecycle (in-memory)', () {
    test('updateRecurringTask changes label, color, and recurrence', () {
      final r = repo();
      final t = r.addRecurringTask(
        label: 'Meds',
        recurrence: const DailyRecurrence(),
        colorHex: '#abc',
      );

      final updated = r.updateRecurringTask(
        t.id,
        label: 'Take meds',
        colorHex: '#def',
        recurrence: WeeklyRecurrence({1, 3, 5}),
      );

      expect(updated.label, 'Take meds');
      expect(updated.colorHex, '#def');
      expect(updated.recurrence, WeeklyRecurrence({1, 3, 5}));
      // Persisted, not just returned.
      expect(r.tasks().single.label, 'Take meds');
      // createdAt is preserved across the edit.
      expect(r.tasks().single.createdAt, t.createdAt);
    });

    test('updateRecurringTask on an unknown id throws', () {
      expect(
        () => repo().updateRecurringTask('nope', label: 'x'),
        throwsStateError,
      );
    });

    test('setTaskArchived hides the task from the tray, and un-archives', () {
      final r = repo();
      final t = r.addRecurringTask(
        label: 'Meds',
        recurrence: const DailyRecurrence(),
        colorHex: '#abc',
      );

      r.setTaskArchived(t.id, archived: true);
      expect(trayFor(today, r.tasks(), r.completions()), isEmpty);
      expect(r.tasks().single.archived, isTrue); // still stored

      r.setTaskArchived(t.id, archived: false);
      expect(trayFor(today, r.tasks(), r.completions()), hasLength(1));
    });

    test('deleteRecurringTask removes the task and its completions', () {
      final r = repo();
      final t = r.addRecurringTask(
        label: 'Meds',
        recurrence: const DailyRecurrence(),
        colorHex: '#abc',
      );
      r.completeTask(t.id, today);
      expect(r.completions(), hasLength(1));

      r.deleteRecurringTask(t.id);
      expect(r.tasks(), isEmpty);
      expect(r.completions(), isEmpty); // parity with FK ON DELETE CASCADE
    });

    test('deleteRecurringTask on an unknown id throws', () {
      expect(() => repo().deleteRecurringTask('nope'), throwsStateError);
    });
  });
}
