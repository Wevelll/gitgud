import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  // Weekday template on Mon–Fri (bits 0..4 = 31), weekend on Sat–Sun (bits
  // 5,6 = 96).
  DayProfile weekday() => DayProfile.fromDurations(
        id: 'weekday',
        name: 'Weekday',
        isDefault: true,
        activeDaysMask: 31,
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Work', colorHex: '#3E7CB1', minutes: 480),
          (name: 'Free', colorHex: '#6FA85B', minutes: 480),
        ],
      );

  DayProfile weekend() => DayProfile.fromDurations(
        id: 'weekend',
        name: 'Weekend',
        activeDaysMask: 96,
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Free', colorHex: '#6FA85B', minutes: 960),
        ],
      );

  group('DayProfile.fromDurations', () {
    test('lays blocks clockwise and validates the 24h sum', () {
      final p = weekday();
      expect(p.segments.map((s) => s.name), ['Sleep', 'Work', 'Free']);
      expect(p.segments[0].startMin, 0);
      expect(p.segments[1].startMin, 480);
      expect(p.segments[2].startMin, 960);
      expect(p.segments[2].endMin, 0); // wraps back to midnight
    });

    test('rejects durations that do not sum to 1440', () {
      expect(
        () => DayProfile.fromDurations(
          id: 'x',
          name: 'X',
          blocks: const [
            (name: 'A', colorHex: '#fff', minutes: 100),
            (name: 'B', colorHex: '#fff', minutes: 100),
          ],
        ),
        throwsA(isA<InvalidProfileException>()),
      );
    });
  });

  group('appliesToWeekday', () {
    test('templates match their assigned weekdays; overrides never do', () {
      expect(weekday().appliesToWeekday(1), isTrue); // Monday
      expect(weekday().appliesToWeekday(6), isFalse); // Saturday
      expect(weekend().appliesToWeekday(7), isTrue); // Sunday
      final override = weekday().copyWith(forDate: '2026-07-20');
      expect(override.appliesToWeekday(1), isFalse); // it's a date override now
    });
  });

  group('effectiveProfile', () {
    final profiles = [weekday(), weekend()];

    test('picks the weekday template for a weekday', () {
      // 2026-07-06 is a Monday.
      expect(effectiveProfile(CivilDate.parse('2026-07-06'), profiles).id,
          'weekday');
    });

    test('picks the weekend template on Saturday', () {
      // 2026-07-11 is a Saturday.
      expect(effectiveProfile(CivilDate.parse('2026-07-11'), profiles).id,
          'weekend');
    });

    test('a per-date override wins over the weekday template', () {
      final override = weekday().copyWith(id: 'd', forDate: '2026-07-06');
      final resolved = effectiveProfile(
          CivilDate.parse('2026-07-06'), [...profiles, override]);
      expect(resolved.id, 'd');
    });

    test('falls back to the default when no weekday assignment matches', () {
      final noMasks = [
        weekday().copyWith(activeDaysMask: 0), // default, unassigned
        weekend().copyWith(activeDaysMask: 0),
      ];
      expect(effectiveProfile(CivilDate.parse('2026-07-06'), noMasks).id,
          'weekday'); // isDefault
    });
  });

  test('forDate survives block edits (a per-date override stays a date)', () {
    final override = weekday().copyWith(id: 'd', forDate: '2026-07-06');
    // Segment ids keep their original prefix from fromDurations.
    final edited = override.updateBlock('weekday.seg1', name: 'Deep work');
    expect(edited.forDate, '2026-07-06');
  });
}
