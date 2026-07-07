import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  group('FocusSession', () {
    test('completing yields a timer-sourced pending log', () {
      const s = FocusSession(
        category: 'Deep Work',
        startTs: '2026-07-07T09:00:00Z',
        segmentId: 'seg-work',
      );
      final log = s.completeAt('2026-07-07T09:25:00Z');
      expect(log.category, 'Deep Work');
      expect(log.segmentId, 'seg-work');
      expect(log.durationMin, 25);
      expect(log.source, LogSource.timer);
    });

    test('rejects an end before the start', () {
      const s = FocusSession(
          category: 'x', startTs: '2026-07-07T09:00:00Z');
      expect(() => s.completeAt('2026-07-07T08:00:00Z'), throwsArgumentError);
    });
  });

  group('pomodoroPlan', () {
    test('classic 25/5 x4 has no trailing break', () {
      final plan = pomodoroPlan();
      expect(plan, hasLength(7)); // 4 work + 3 breaks
      expect(plan.first,
          const PomodoroInterval(phase: PomodoroPhase.work, startOffsetMin: 0, endOffsetMin: 25));
      expect(plan[1].phase, PomodoroPhase.shortBreak);
      expect(plan.last.phase, PomodoroPhase.work);
      expect(plan.last.endOffsetMin, 25 * 4 + 5 * 3);
    });

    test('long break replaces the short break on the cycle boundary', () {
      final plan = pomodoroPlan(cycles: 4, longBreakMin: 15, longBreakEvery: 2);
      final longs = plan.where((p) => p.phase == PomodoroPhase.longBreak);
      expect(longs, hasLength(1)); // after the 2nd work (4th is last, no break)
      expect(longs.single.durationMin, 15);
    });

    test('rejects nonsense', () {
      expect(() => pomodoroPlan(cycles: 0), throwsArgumentError);
    });
  });
}
