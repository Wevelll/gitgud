import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  final date = CivilDate.parse('2026-07-07');
  final stamp = DateTime.utc(2026, 7, 7, 12);

  TimeLog log(String id, String start, String end, String cat,
          {String? note}) =>
      TimeLog(
        id: id,
        date: CivilDate.fromDateTime(DateTime.parse(start)),
        startTs: start,
        endTs: end,
        category: cat,
        note: note,
      );

  group('CSV', () {
    test('time logs export with header and one row per log', () {
      final csv = timeLogsToCsv([
        log('1', '2026-07-07T09:00:00Z', '2026-07-07T10:30:00Z', 'Work'),
      ]);
      final lines = csv.split('\r\n');
      expect(lines.first,
          'date,start,end,durationMin,category,segmentId,note,source');
      expect(lines[1], contains('2026-07-07'));
      expect(lines[1], contains('90')); // duration minutes
      expect(lines[1], contains('Work'));
    });

    test('fields with commas/quotes are escaped per RFC 4180', () {
      final csv = timeLogsToCsv([
        log('1', '2026-07-07T09:00:00Z', '2026-07-07T10:00:00Z', 'Work',
            note: 'a, "b"'),
      ]);
      expect(csv, contains('"a, ""b"""'));
    });

    test('empty log set still emits the header', () {
      expect(timeLogsToCsv(const []),
          'date,start,end,durationMin,category,segmentId,note,source');
    });

    test('variance export', () {
      final csv = varianceToCsv(const [
        CategoryVariance(category: 'Sleep', plannedMin: 480, actualMin: 380),
      ]);
      final lines = csv.split('\r\n');
      expect(lines.first, 'category,plannedMin,actualMin,deltaMin');
      expect(lines[1], 'Sleep,480,380,-100');
    });
  });

  group('ICS', () {
    final profile = DayProfile.fromDurations(
      id: 'p',
      name: 'Weekday',
      blocks: const [
        (name: 'Sleep', colorHex: '#111', minutes: 480), // 00:00-08:00
        (name: 'Work', colorHex: '#222', minutes: 480), // 08:00-16:00
        (name: 'Free', colorHex: '#333', minutes: 480), // 16:00-24:00
      ],
    );

    test('segments become VEVENTs with UTC stamps', () {
      final ics = segmentsToIcs(profile, date, dtStamp: stamp);
      expect(ics, startsWith('BEGIN:VCALENDAR'));
      expect(ics.trim(), endsWith('END:VCALENDAR'));
      expect('VEVENT'.allMatches(ics).length, 6); // BEGIN+END x3
      expect(ics, contains('SUMMARY:Work'));
      expect(ics, contains('DTSTART:20260707T080000Z'));
      expect(ics, contains('DTEND:20260707T160000Z'));
    });

    test('a midnight-wrapping segment ends on the next calendar day', () {
      final wrap = DayProfile.fromDurations(
        id: 'w',
        name: 'Night',
        blocks: const [
          (name: 'Evening', colorHex: '#1', minutes: 60), // 00:00-01:00
          (name: 'Sleep', colorHex: '#2', minutes: 1380), // 01:00-24:00
        ],
        firstStartMin: 23 * 60, // shift so Sleep wraps: 00:00 Sleep? build below
      );
      // Simpler explicit wrap: Sleep 23:00 -> 07:00 next day.
      final night = DayProfile.ring(
        id: 'n',
        name: 'n',
        spans: const [
          (startMin: 420, name: 'Day', colorHex: '#1'), // 07:00
          (startMin: 1380, name: 'Sleep', colorHex: '#2'), // 23:00 -> wraps
        ],
      );
      expect(wrap.segments, isNotEmpty); // fromDurations still valid
      final ics = segmentsToIcs(night, date, dtStamp: stamp);
      expect(ics, contains('DTSTART:20260707T230000Z'));
      expect(ics, contains('DTEND:20260708T070000Z')); // next day
    });

    test('time logs become VEVENTs', () {
      final ics = timeLogsToIcs([
        log('1', '2026-07-07T09:00:00Z', '2026-07-07T10:30:00Z', 'Work'),
      ], dtStamp: stamp);
      expect(ics, contains('SUMMARY:Work'));
      expect(ics, contains('DTSTART:20260707T090000Z'));
      expect(ics, contains('DTEND:20260707T103000Z'));
    });

    test('special characters in a summary are escaped', () {
      final ics = timeLogsToIcs([
        log('1', '2026-07-07T09:00:00Z', '2026-07-07T10:00:00Z', 'a;b,c'),
      ], dtStamp: stamp);
      expect(ics, contains(r'SUMMARY:a\;b\,c'));
    });
  });
}
