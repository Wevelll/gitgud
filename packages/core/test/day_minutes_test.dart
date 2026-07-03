import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  group('spanMinutes (clockwise distance)', () {
    test('same-day forward span', () {
      expect(spanMinutes(540, 780), 240); // 09:00 -> 13:00
    });

    test('midnight-wrapping span', () {
      expect(spanMinutes(1380, 420), 480); // 23:00 -> 07:00 = 8h
    });

    test('full loop is zero, not 1440', () {
      expect(spanMinutes(600, 600), 0);
    });

    test('negative delta wraps to positive', () {
      expect(spanMinutes(60, 0), 1380); // 01:00 -> 00:00 clockwise
    });
  });

  group('normalizeMinute', () {
    test('wraps over and under the day', () {
      expect(normalizeMinute(1500), 60);
      expect(normalizeMinute(-30), 1410);
      expect(normalizeMinute(0), 0);
    });
  });

  group('parseMinuteOfDay', () {
    test('parses HH:MM', () {
      expect(parseMinuteOfDay('07:30'), 450);
      expect(parseMinuteOfDay('00:00'), 0);
      expect(parseMinuteOfDay('23:59'), 1439);
    });

    test('parses bare minute integers', () {
      expect(parseMinuteOfDay('450'), 450);
    });

    test('rejects out-of-range and garbage', () {
      expect(() => parseMinuteOfDay('24:00'), throwsFormatException);
      expect(() => parseMinuteOfDay('12:60'), throwsFormatException);
      expect(() => parseMinuteOfDay('1440'), throwsFormatException);
      expect(() => parseMinuteOfDay('noon'), throwsFormatException);
      expect(() => parseMinuteOfDay('1:2:3'), throwsFormatException);
    });
  });

  group('formatting', () {
    test('formatMinuteOfDay pads and normalizes', () {
      expect(formatMinuteOfDay(450), '07:30');
      expect(formatMinuteOfDay(0), '00:00');
      expect(formatMinuteOfDay(1500), '01:00'); // normalized
    });

    test('formatDuration matches prototype fmtDur', () {
      expect(formatDuration(90), '1h 30m');
      expect(formatDuration(45), '45m');
      expect(formatDuration(120), '2h');
      expect(formatDuration(0), '0m');
    });
  });
}
