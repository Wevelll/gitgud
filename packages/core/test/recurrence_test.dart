import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final fri = CivilDate.parse('2026-07-03'); // Friday (weekday 5)
  final sat = fri.addDays(1);
  final mon = fri.addDays(3);

  group('DailyRecurrence', () {
    test('always due', () {
      const r = DailyRecurrence();
      expect(r.isDueOn(fri), isTrue);
      expect(r.isDueOn(sat), isTrue);
    });
  });

  group('WeeklyRecurrence', () {
    test('due only on listed weekdays', () {
      final r = WeeklyRecurrence({5, 1}); // Fri + Mon
      expect(r.isDueOn(fri), isTrue);
      expect(r.isDueOn(mon), isTrue);
      expect(r.isDueOn(sat), isFalse);
    });

    test('validates weekday range and non-empty', () {
      expect(() => WeeklyRecurrence(<int>{}), throwsArgumentError);
      expect(() => WeeklyRecurrence({0}), throwsArgumentError);
      expect(() => WeeklyRecurrence({8}), throwsArgumentError);
    });
  });

  group('IntervalRecurrence', () {
    final r = IntervalRecurrence(3, fri); // every 3 days from Fri

    test('fires on the anchor and every interval after', () {
      expect(r.isDueOn(fri), isTrue);
      expect(r.isDueOn(fri.addDays(3)), isTrue);
      expect(r.isDueOn(fri.addDays(6)), isTrue);
    });

    test('does not fire off-cycle or before the anchor', () {
      expect(r.isDueOn(fri.addDays(1)), isFalse);
      expect(r.isDueOn(fri.addDays(2)), isFalse);
      expect(r.isDueOn(fri.addDays(-3)), isFalse); // before anchor
    });

    test('validates interval', () {
      expect(() => IntervalRecurrence(0, fri), throwsArgumentError);
    });
  });

  group('DatesRecurrence', () {
    final r = DatesRecurrence({fri, mon});
    test('due only on listed dates', () {
      expect(r.isDueOn(fri), isTrue);
      expect(r.isDueOn(mon), isTrue);
      expect(r.isDueOn(sat), isFalse);
    });
    test('rejects empty', () {
      expect(() => DatesRecurrence(<CivilDate>{}), throwsArgumentError);
    });
  });

  group('encode / parse round-trip', () {
    final cases = <Recurrence>[
      const DailyRecurrence(),
      WeeklyRecurrence({5, 1, 3}),
      IntervalRecurrence(4, fri),
      DatesRecurrence({mon, fri}),
    ];

    test('every rule round-trips', () {
      for (final rule in cases) {
        expect(Recurrence.parse(rule.encode()), rule, reason: rule.encode());
      }
    });

    test('encodings are canonical (sorted)', () {
      expect(WeeklyRecurrence({5, 1, 3}).encode(), 'weekly:1,3,5');
      expect(IntervalRecurrence(4, fri).encode(), 'interval:4@2026-07-03');
      expect(
          DatesRecurrence({mon, fri}).encode(), 'dates:2026-07-03,2026-07-06');
    });

    test('rejects unknown rules', () {
      expect(() => Recurrence.parse('yearly'), throwsFormatException);
      expect(() => Recurrence.parse('weekly'), throwsFormatException);
    });
  });
}
