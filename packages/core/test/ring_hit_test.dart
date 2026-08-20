import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

/// Grabbing a boundary on the ring — the model half of drag-to-resize
/// (SPEC §2.4). Midnight-wrap is the whole point of these tests: a boundary at
/// 00:00 must be grabbable from just before midnight (golden rule #8).
void main() {
  // Sleep 23:00–07:00 (wraps), Work 07:00–15:00, Free 15:00–23:00.
  DayProfile profile() => DayProfile.ring(
        id: 'p',
        name: 'Day',
        segmentIds: const ['sleep', 'work', 'free'],
        spans: const [
          (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
          (startMin: 420, name: 'Work', colorHex: '#3E7CB1'),
          (startMin: 900, name: 'Free', colorHex: '#6FA85B'),
        ],
      );

  group('boundaryDistance', () {
    test('takes the short way round the ring', () {
      expect(boundaryDistance(0, 1435), 5);
      expect(boundaryDistance(1435, 0), 5);
      expect(boundaryDistance(420, 450), 30);
      expect(boundaryDistance(0, 720), 720); // antipodal
    });
  });

  group('snapMinute', () {
    test('rounds to the step', () {
      expect(snapMinute(422), 420);
      expect(snapMinute(423), 425);
      expect(snapMinute(431, stepMin: 15), 435);
    });

    test('wraps rather than producing 1440', () {
      expect(snapMinute(1438), 0);
      expect(snapMinute(1439, stepMin: 15), 0);
    });
  });

  group('boundaryNear', () {
    test('finds the boundary under a nearby minute', () {
      expect(profile().boundaryNear(425)?.id, 'sleep'); // Sleep ends 07:00
      expect(profile().boundaryNear(898)?.id, 'work'); // Work ends 15:00
    });

    test('returns null when nothing is within tolerance', () {
      expect(profile().boundaryNear(600), isNull); // mid-Work
    });

    test('a boundary at midnight is grabbable from before midnight', () {
      // Free 15:00–23:00 ends at 23:00; grab it from 22:52.
      expect(profile().boundaryNear(1372)?.id, 'free');

      // And a ring whose boundary sits exactly on midnight is reachable from
      // 23:55 — the wrap case that a plain subtraction would miss.
      final midnight = DayProfile.ring(
        id: 'm',
        name: 'M',
        segmentIds: const ['night', 'day'],
        spans: const [
          (startMin: 0, name: 'Night', colorHex: '#4B4FA6'),
          (startMin: 720, name: 'Day', colorHex: '#6FA85B'),
        ],
      );
      expect(midnight.boundaryNear(1435)?.id, 'day'); // Day ends 00:00
      expect(midnight.boundaryNear(5)?.id, 'day');
    });

    test('picks the nearer of two candidate boundaries', () {
      // 07:00 (Sleep's end) vs 15:00 — 07:06 is nearest 07:00.
      expect(profile().boundaryNear(426)?.id, 'sleep');
      // Tolerance is respected exactly at the edge.
      expect(profile().boundaryNear(420 + 18, toleranceMin: 18)?.id, 'sleep');
      expect(profile().boundaryNear(420 + 19, toleranceMin: 18), isNull);
    });
  });
}
