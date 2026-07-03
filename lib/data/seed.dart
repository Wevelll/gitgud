import 'package:day_dial_core/day_dial_core.dart';

/// A default day layout for the UI, mirroring the prototype's `INITIAL` ring.
/// (Persistence will supply the real profile later; this seeds the demo.)
DayProfile defaultProfile() => DayProfile.ring(
  id: 'weekday',
  name: 'Weekday',
  isDefault: true,
  segmentIds: const ['sleep', 'morning', 'deep', 'lunch', 'work', 'free'],
  spans: const [
    (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
    (startMin: 420, name: 'Morning', colorHex: '#C98A3E'),
    (startMin: 540, name: 'Deep work', colorHex: '#2E8B8B'),
    (startMin: 780, name: 'Lunch', colorHex: '#B5624F'),
    (startMin: 840, name: 'Work', colorHex: '#3E7CB1'),
    (startMin: 1080, name: 'Free time', colorHex: '#6FA85B'),
  ],
);

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
