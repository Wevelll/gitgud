import 'package:day_dial_core/day_dial_core.dart';

/// A default day layout, mirroring the prototype's `INITIAL` ring. Used to seed
/// the dev server and as a sane starting point before persistence lands.
DayProfile defaultWeekdayProfile() => DayProfile.ring(
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
