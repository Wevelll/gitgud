import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final date = CivilDate.parse('2026-07-03');

  TimeLog log(String start, String end, {String category = 'Work'}) => TimeLog(
        id: 'l',
        date: date,
        startTs: start,
        endTs: end,
        category: category,
      );

  test('same-day duration', () {
    expect(
        log('2026-07-03T09:00:00Z', '2026-07-03T11:30:00Z').durationMin, 150);
  });

  test('duration across midnight just works (instants, not minute-of-day)', () {
    expect(
        log('2026-07-03T23:00:00Z', '2026-07-04T01:00:00Z').durationMin, 120);
  });

  test('zero-length log is allowed', () {
    expect(log('2026-07-03T09:00:00Z', '2026-07-03T09:00:00Z').durationMin, 0);
  });

  test('end before start is rejected', () {
    expect(
      () => log('2026-07-03T11:00:00Z', '2026-07-03T10:00:00Z'),
      throwsArgumentError,
    );
  });

  test('source defaults to manual', () {
    expect(log('2026-07-03T09:00:00Z', '2026-07-03T10:00:00Z').source,
        LogSource.manual);
  });
}
