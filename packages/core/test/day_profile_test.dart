import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

/// The prototype's INITIAL ring (dial_example.jsx), our behavioral reference.
DayProfile buildInitial() => DayProfile.ring(
      id: 'weekday',
      name: 'Weekday',
      isDefault: true,
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'), // 23:00
        (startMin: 420, name: 'Morning', colorHex: '#C98A3E'), // 07:00
        (startMin: 540, name: 'Deep work', colorHex: '#2E8B8B'), // 09:00
        (startMin: 780, name: 'Lunch', colorHex: '#B5624F'), // 13:00
        (startMin: 840, name: 'Work', colorHex: '#3E7CB1'), // 14:00
        (startMin: 1080, name: 'Free time', colorHex: '#6FA85B'), // 18:00
      ],
    );

int _sumDurations(DayProfile p) =>
    p.segments.fold(0, (acc, s) => acc + s.durationMin);

void main() {
  group('ring construction', () {
    test('is contiguous and sums to 1440', () {
      final p = buildInitial();
      expect(_sumDurations(p), 1440);
      for (var i = 0; i < p.segments.length; i++) {
        final next = p.segments[(i + 1) % p.segments.length];
        expect(p.segments[i].endMin, next.startMin);
      }
    });

    test('durations match the reference layout', () {
      final p = buildInitial();
      expect(p.segments.map((s) => s.durationMin).toList(),
          [480, 120, 240, 60, 240, 300]);
    });

    test('Sleep wraps midnight', () {
      final p = buildInitial();
      expect(p.segments.first.wrapsMidnight, isTrue);
    });
  });

  group('current / next / remaining', () {
    final p = buildInitial();

    test('indexAt picks the right wedge, including across midnight', () {
      expect(p.indexAt(0), 0); // 00:00 -> Sleep
      expect(p.indexAt(419), 0); // 06:59 -> Sleep
      expect(p.indexAt(420), 1); // 07:00 -> Morning
      expect(p.indexAt(450), 1); // 07:30 -> Morning
      expect(p.indexAt(1380), 0); // 23:00 exactly -> Sleep (start-inclusive)
    });

    test('remaining accounts for the wrap', () {
      expect(p.remainingAt(0), 420); // 8h - 60m elapsed since 23:00
      expect(p.remainingAt(1380), 480); // fresh into Sleep
    });

    test('nextAfter wraps around the ring', () {
      expect(p.nextAfter(1080).name, 'Sleep'); // after Free time -> Sleep
      expect(p.nextAfter(0).name, 'Morning'); // after Sleep -> Morning
    });
  });

  group('resizeBoundary', () {
    final p = buildInitial();

    test('grows one segment and shrinks its neighbor, sum preserved', () {
      final r = p.resizeBoundary(0, 15); // Sleep/Morning boundary +15
      expect(r.segments[0].durationMin, 495);
      expect(r.segments[1].durationMin, 105);
      expect(_sumDurations(r), 1440);
    });

    test('works on a wrapping boundary (Free time / Sleep)', () {
      final r = p.resizeBoundary(5, 30);
      expect(r.segments[5].durationMin, 330);
      expect(r.segments[0].durationMin, 450);
      expect(r.segments[0].wrapsMidnight, isTrue); // still wraps
      expect(_sumDurations(r), 1440);
    });

    test('rejects shrinking a neighbor below the 15-min minimum', () {
      // Lunch is 60m; pulling its start-boundary would leave <15m.
      final r = p.resizeBoundary(3, -50);
      expect(identical(r, p), isTrue); // unchanged
    });

    test('rejects growing past the combined-minus-minimum limit', () {
      final r = p.resizeBoundary(3, 230); // would starve Work
      expect(identical(r, p), isTrue);
    });

    test('negative delta on the first boundary', () {
      final r = p.resizeBoundary(0, -60); // Sleep shrinks, Morning grows
      expect(r.segments[0].durationMin, 420);
      expect(r.segments[1].durationMin, 180);
      expect(_sumDurations(r), 1440);
    });

    test('out-of-range index throws', () {
      expect(() => p.resizeBoundary(99, 15), throwsRangeError);
    });
  });

  group('validation', () {
    test('rejects a gap between segments', () {
      expect(
        () => DayProfile(id: 'p', name: 'p', segments: const [
          Segment(
              id: 'a', name: 'a', colorHex: '#000', startMin: 0, endMin: 600),
          // gap: next starts at 700, not 600
          Segment(
              id: 'b', name: 'b', colorHex: '#000', startMin: 700, endMin: 0),
        ]),
        throwsA(isA<InvalidProfileException>()),
      );
    });

    test('rejects a too-short segment', () {
      expect(
        () => DayProfile(id: 'p', name: 'p', segments: const [
          Segment(
              id: 'a', name: 'a', colorHex: '#000', startMin: 0, endMin: 10),
          Segment(
              id: 'b', name: 'b', colorHex: '#000', startMin: 10, endMin: 0),
        ]),
        throwsA(isA<InvalidProfileException>()),
      );
    });

    test('rejects a contiguous ring whose durations do not sum to 1440', () {
      // Two full-day segments: cyclically contiguous (0->0, 0->0) so they pass
      // the gap check, but their durations sum to 2880. Exercises the sum guard.
      expect(
        () => DayProfile(id: 'p', name: 'p', segments: const [
          Segment(id: 'a', name: 'a', colorHex: '#000', startMin: 0, endMin: 0),
          Segment(id: 'b', name: 'b', colorHex: '#000', startMin: 0, endMin: 0),
        ]),
        throwsA(isA<InvalidProfileException>()),
      );
    });
  });
}
