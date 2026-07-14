import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  // Sleep 00:00-08:00, Work 08:00-16:00, Free 16:00-24:00.
  final profile = DayProfile.fromDurations(
    id: 'p',
    name: 'Weekday',
    blocks: const [
      (name: 'Sleep', colorHex: '#1', minutes: 480),
      (name: 'Work', colorHex: '#2', minutes: 480),
      (name: 'Free', colorHex: '#3', minutes: 480),
    ],
  );

  int ms(int minutes) => minutes * 60 * 1000;

  test('isIdle triggers only past the threshold', () {
    expect(
        isIdle(
            lastActivityEpochMs: 0, nowEpochMs: ms(10), thresholdMinutes: 15),
        isFalse);
    expect(
        isIdle(
            lastActivityEpochMs: 0, nowEpochMs: ms(20), thresholdMinutes: 15),
        isTrue);
  });

  test('no nudge below the threshold', () {
    final nudge = buildIdleNudge(
      lastActivityEpochMs: 0,
      nowEpochMs: ms(5),
      thresholdMinutes: 15,
      profile: profile,
      nowMinuteOfDay: 10 * 60,
    );
    expect(nudge, isNull);
  });

  test('nudge covers the single segment the away span sat in', () {
    // Away 09:00 -> 09:40 (40 min), entirely inside Work.
    final nudge = buildIdleNudge(
      lastActivityEpochMs: ms(9 * 60),
      nowEpochMs: ms(9 * 60 + 40),
      thresholdMinutes: 15,
      profile: profile,
      nowMinuteOfDay: 9 * 60 + 40,
    )!;
    expect(nudge.awayMinutes, 40);
    expect(nudge.fromMin, 9 * 60);
    expect(nudge.toMin, 9 * 60 + 40);
    expect(nudge.coveredSegments.map((s) => s.name), ['Work']);
    expect(nudge.suggestedCategory, 'Work');
  });

  test('a long away span covers several segments in ring order', () {
    // Away 07:30 -> 16:30 (9h): starts in Sleep, through Work, into Free.
    final nudge = buildIdleNudge(
      lastActivityEpochMs: ms(7 * 60 + 30),
      nowEpochMs: ms(16 * 60 + 30),
      thresholdMinutes: 15,
      profile: profile,
      nowMinuteOfDay: 16 * 60 + 30,
    )!;
    expect(nudge.coveredSegments.map((s) => s.name), ['Sleep', 'Work', 'Free']);
    expect(nudge.suggestedCategory, 'Sleep');
  });
}
