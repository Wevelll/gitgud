import 'package:day_dial_core/day_dial_core.dart';

/// An in-memory repository seeded with the reference day and one demo task —
/// injected into the app in widget tests (no SQLite, no files).
DayRepository testRepository() {
  final repo = InMemoryDayRepository(profiles: [testProfile()]);
  repo.addRecurringTask(
    label: 'Take meds',
    recurrence: const DailyRecurrence(),
    colorHex: '#3E7CB1',
  );
  return repo;
}

/// The prototype's reference ring, used across the widget tests.
DayProfile testProfile() => DayProfile.ring(
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
