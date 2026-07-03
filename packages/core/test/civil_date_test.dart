import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('parses a valid date', () {
      final d = CivilDate.parse('2026-07-03');
      expect(d.year, 2026);
      expect(d.month, 7);
      expect(d.day, 3);
    });

    test('rejects impossible and malformed dates', () {
      expect(() => CivilDate.parse('2026-02-30'), throwsFormatException);
      expect(() => CivilDate.parse('2026-13-01'), throwsFormatException);
      expect(() => CivilDate.parse('2026-7-3'), throwsFormatException);
      expect(() => CivilDate.parse('nope'), throwsFormatException);
    });

    test('round-trips through iso', () {
      expect(CivilDate.parse('2026-01-09').iso, '2026-01-09');
    });
  });

  group('calendar math', () {
    final fri = CivilDate.parse('2026-07-03'); // a Friday

    test('weekday is ISO (Mon=1..Sun=7)', () {
      expect(fri.weekday, 5);
      expect(fri.addDays(1).weekday, 6); // Saturday
      expect(fri.addDays(2).weekday, 7); // Sunday
      expect(fri.addDays(3).weekday, 1); // Monday
    });

    test('addDays crosses month and year boundaries', () {
      expect(CivilDate.parse('2026-01-31').addDays(1).iso, '2026-02-01');
      expect(CivilDate.parse('2026-12-31').addDays(1).iso, '2027-01-01');
      expect(CivilDate.parse('2026-03-01').addDays(-1).iso, '2026-02-28');
    });

    test('daysUntil is signed', () {
      expect(fri.daysUntil(fri.addDays(10)), 10);
      expect(fri.daysUntil(fri.addDays(-3)), -3);
    });

    test('rangeTo is inclusive; empty when reversed', () {
      final r = fri.rangeTo(fri.addDays(2));
      expect(r.map((d) => d.iso).toList(),
          ['2026-07-03', '2026-07-04', '2026-07-05']);
      expect(fri.rangeTo(fri.addDays(-1)), isEmpty);
    });

    test('ordering and equality', () {
      expect(fri.isBefore(fri.addDays(1)), isTrue);
      expect(fri.isAfter(fri.addDays(-1)), isTrue);
      expect(fri == CivilDate.parse('2026-07-03'), isTrue);
      final sorted = [fri.addDays(2), fri, fri.addDays(1)]..sort();
      expect(sorted.first, fri);
    });
  });
}
