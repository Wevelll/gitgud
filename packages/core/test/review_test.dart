import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final asOf = CivilDate.parse('2026-07-07');

  final profile = DayProfile.fromDurations(
    id: 'p',
    name: 'Weekday',
    blocks: const [
      (name: 'Sleep', colorHex: '#1', minutes: 480),
      (name: 'Work', colorHex: '#2', minutes: 480),
      (name: 'Free', colorHex: '#3', minutes: 480),
    ],
  );

  RecurringTask task(String id) => RecurringTask(
        id: id,
        label: id,
        colorHex: '#fff',
        recurrence: const DailyRecurrence(),
        createdAt: '2026-01-01T00:00:00Z',
      );

  TaskCompletion done(String taskId, CivilDate date) => TaskCompletion(
      id: '$taskId@${date.iso}', taskId: taskId, date: date, completedAt: '${date.iso}T09:00:00Z');

  test('ReviewRange date windows end at the reference day', () {
    expect(ReviewRange.day.datesEndingAt(asOf), [asOf]);
    expect(ReviewRange.week.datesEndingAt(asOf).length, 7);
    expect(ReviewRange.month.datesEndingAt(asOf).length, 30);
    expect(ReviewRange.year.datesEndingAt(asOf).length, 365);
    expect(ReviewRange.week.datesEndingAt(asOf).last, asOf);
  });

  test('review aggregates variance, streaks, completion, calendar load', () {
    final tasks = [task('meds')];
    // Completed the last 3 days of the week window.
    final completions = [
      for (var i = 0; i < 3; i++) done('meds', asOf.addDays(-i)),
    ];

    final calendar = InMemoryCalendarProvider([
      CalendarEvent(
        id: 'm',
        sourceId: 's',
        uid: 'm',
        title: 'Meeting',
        startTs: '2026-07-07T10:00:00',
        endTs: '2026-07-07T11:00:00',
      ),
    ]);

    final review = buildReview(
      range: ReviewRange.week,
      asOf: asOf,
      profileForDate: (_) => profile,
      logs: const [],
      tasks: tasks,
      completions: completions,
      habits: const [],
      habitEvents: const [],
      calendar: calendar,
    );

    // 7 days planned, Sleep/Work/Free 8h each => 7*480 planned per category.
    final sleep = review.variance.firstWhere((v) => v.category == 'Sleep');
    expect(sleep.plannedMin, 7 * 480);
    expect(sleep.actualMin, 0);

    expect(review.dueTaskInstances, 7); // daily task over 7 days
    expect(review.completedTaskInstances, 3);
    expect(review.taskCompletionRate, closeTo(3 / 7, 1e-9));

    // Current streak counts back from asOf: 3 completed days.
    expect(review.taskStreaks.single.streak.current, 3);

    // One 60-minute meeting on 07-07 in the window.
    expect(review.calendarMinutes, 60);
  });

  test('no calendar => zero calendar minutes', () {
    final review = buildReview(
      range: ReviewRange.day,
      asOf: asOf,
      profileForDate: (_) => profile,
      logs: const [],
      tasks: const [],
      completions: const [],
      habits: const [],
      habitEvents: const [],
    );
    expect(review.calendarMinutes, 0);
    expect(review.taskCompletionRate, 0);
  });
}
