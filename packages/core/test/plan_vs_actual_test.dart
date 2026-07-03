import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

/// A profile with two blocks named "Work" to prove same-name accumulation.
DayProfile profile() => DayProfile.ring(
      id: 'p',
      name: 'p',
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#000'), // 23:00, 480m
        (startMin: 420, name: 'Work', colorHex: '#000'), // 07:00, 360m
        (startMin: 780, name: 'Lunch', colorHex: '#000'), // 13:00, 60m
        (startMin: 840, name: 'Work', colorHex: '#000'), // 14:00, 240m
        (startMin: 1080, name: 'Free', colorHex: '#000'), // 18:00, 300m
      ],
    );

void main() {
  final fri = CivilDate.parse('2026-07-03');
  final sat = fri.addDays(1);

  group('plannedByCategory', () {
    test('sums duration per category, merging same-named blocks', () {
      expect(plannedByCategory(profile()), {
        'Sleep': 480,
        'Work': 600, // 360 + 240
        'Lunch': 60,
        'Free': 300,
      });
    });
  });

  group('mergeVariance', () {
    test('unions categories, sorts, computes signed delta', () {
      final v = mergeVariance(
          {'Work': 480, 'Sleep': 480}, {'Work': 300, 'Exercise': 45});
      expect(v.map((e) => e.category).toList(),
          ['Exercise', 'Sleep', 'Work']); // sorted
      final work = v.firstWhere((e) => e.category == 'Work');
      expect(work.deltaMin, -180); // 300 - 480, under plan
      final ex = v.firstWhere((e) => e.category == 'Exercise');
      expect(ex.plannedMin, 0); // actual-only category
    });
  });

  group('planVsActual over a range', () {
    test('scales planned across days and filters logs to the range', () {
      final dates = fri.rangeTo(sat); // 2 days, same profile
      final logs = [
        TimeLog(
            id: '1',
            date: fri,
            category: 'Work',
            startTs: '2026-07-03T09:00:00Z',
            endTs: '2026-07-03T12:00:00Z'),
        TimeLog(
            id: '2',
            date: sat,
            category: 'Work',
            startTs: '2026-07-04T14:00:00Z',
            endTs: '2026-07-04T16:00:00Z'),
        TimeLog(
            id: '3',
            date: fri,
            category: 'Exercise',
            startTs: '2026-07-03T18:00:00Z',
            endTs: '2026-07-03T18:45:00Z'),
        // Out of range — must be excluded.
        TimeLog(
            id: '4',
            date: fri.addDays(5),
            category: 'Work',
            startTs: '2026-07-08T09:00:00Z',
            endTs: '2026-07-08T17:00:00Z'),
      ];

      final result = planVsActual(
        dates: dates,
        profileForDate: (_) => profile(),
        logs: logs,
      );
      final byCat = {for (final v in result) v.category: v};

      // Planned scales by 2 days.
      expect(byCat['Work']!.plannedMin, 1200); // 600 * 2
      expect(byCat['Sleep']!.plannedMin, 960); // 480 * 2

      // Actual sums only in-range logs (3h + 2h Work; the day-8 log excluded).
      expect(byCat['Work']!.actualMin, 300);
      expect(byCat['Work']!.deltaMin, -900);

      // Actual-only category surfaces with planned 0.
      expect(byCat['Exercise']!.plannedMin, 0);
      expect(byCat['Exercise']!.actualMin, 45);

      // Planned-only category surfaces with actual 0.
      expect(byCat['Free']!.actualMin, 0);
      expect(byCat['Free']!.plannedMin, 600);
    });
  });
}
