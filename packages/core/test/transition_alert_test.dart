import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  // Sleep 23:00–07:00, Morning 07:00–09:00, Work 09:00–23:00.
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

  test('alerts count minutes forward to each upcoming block', () {
    final alerts = transitionAlerts(profile(), fromMin: 450, count: 2); // 07:30
    expect(alerts.map((a) => a.block.name), ['Work', 'Sleep']);
    expect(alerts[0].minutesUntil, 90); // 07:30 -> 09:00
    expect(alerts[0].message, 'Work starts now');
    expect(alerts[1].minutesUntil, 930); // -> next 23:00
  });

  test('leadMinutes fires earlier with an "in N min" message', () {
    final alerts =
        transitionAlerts(profile(), fromMin: 450, count: 1, leadMinutes: 5);
    expect(alerts.single.minutesUntil, 85);
    expect(alerts.single.message, 'Work starts in 5 min');
  });

  test('a lead longer than the gap clamps to fire now', () {
    // 08:59 -> Work at 09:00 is 1 minute away, but a 5-minute lead is longer.
    final alerts =
        transitionAlerts(profile(), fromMin: 539, count: 1, leadMinutes: 5);
    expect(alerts.single.minutesUntil, 0);
  });

  test('the next transition wraps across midnight', () {
    final alerts =
        transitionAlerts(profile(), fromMin: 1400, count: 1); // 23:20
    expect(alerts.single.block.name, 'Morning'); // 07:00 next day
    expect(alerts.single.minutesUntil, 460); // 23:20 -> 07:00
  });
}
