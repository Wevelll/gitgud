import 'package:day_dial_core/day_dial_core.dart';

/// The first-run default template: a simple 8/8/8 Sleep/Work/Free day (SPEC
/// §2.4). It carries no weekday assignment, so it's the fallback for every day
/// until the user adds weekday-specific templates in settings.
DayProfile defaultProfile() => DayProfile.fromDurations(
  id: 'default',
  name: 'Default',
  isDefault: true,
  segmentIds: const ['sleep', 'work', 'free'],
  blocks: const [
    (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
    (name: 'Work', colorHex: '#3E7CB1', minutes: 480),
    (name: 'Free', colorHex: '#6FA85B', minutes: 480),
  ],
);

/// Demo countable habits seeded on first run: a good one with a target and a
/// bad one to keep an eye on.
List<({String label, String colorHex, HabitPolarity polarity, int? target})>
demoHabits() => const [
  (
    label: 'Water',
    colorHex: '#3E7CB1',
    polarity: HabitPolarity.good,
    target: 8,
  ),
  (
    label: 'Cigarettes',
    colorHex: '#B5624F',
    polarity: HabitPolarity.bad,
    target: null,
  ),
];

/// Demo "must-do today" tasks (all daily), until the tray is wired to the store.
List<RecurringTask> demoTasks() => [
  RecurringTask(
    id: 'meds',
    label: 'Take meds',
    colorHex: '#3E7CB1',
    recurrence: const DailyRecurrence(),
    createdAt: '2026-07-01T08:00:00Z',
  ),
  RecurringTask(
    id: 'stretch',
    label: '20 min stretch',
    colorHex: '#6FA85B',
    recurrence: const DailyRecurrence(),
    createdAt: '2026-07-01T08:00:00Z',
  ),
];
