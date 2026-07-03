import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  group('Segment.durationMin', () {
    test('same-day segment', () {
      const s = Segment(
          id: 'a', name: 'x', colorHex: '#fff', startMin: 540, endMin: 780);
      expect(s.durationMin, 240);
    });

    test('midnight-wrapping segment (23:00-07:00)', () {
      const s = Segment(
          id: 'sleep',
          name: 'Sleep',
          colorHex: '#fff',
          startMin: 1380,
          endMin: 420);
      expect(s.durationMin, 480);
      expect(s.wrapsMidnight, isTrue);
    });

    test('start==end means full day, not zero', () {
      const s = Segment(
          id: 'all', name: 'All', colorHex: '#fff', startMin: 0, endMin: 0);
      expect(s.durationMin, minutesPerDay);
    });
  });

  group('Segment.contains', () {
    const sleep = Segment(
        id: 'sleep',
        name: 'Sleep',
        colorHex: '#fff',
        startMin: 1380,
        endMin: 420);

    test('start-inclusive', () {
      expect(sleep.contains(1380), isTrue);
    });

    test('end-exclusive', () {
      expect(sleep.contains(420), isFalse);
    });

    test('across the midnight boundary', () {
      expect(sleep.contains(0), isTrue); // 00:00
      expect(sleep.contains(419), isTrue); // 06:59 still asleep
    });

    test('outside', () {
      expect(sleep.contains(600), isFalse); // 10:00
    });

    test('normalizes out-of-range query minutes', () {
      expect(sleep.contains(1440), isTrue); // == 00:00
    });
  });
}
