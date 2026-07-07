import '../models/day_profile.dart';
import '../models/segment.dart';
import '../time/day_minutes.dart';

/// A pending "you were away" nudge (SPEC §12.2): how long the user was idle, the
/// wall-clock span, and which planned segments that span covered — so the UI can
/// prompt "log this, or adjust?".
///
/// Pure data. It **never** writes an actual on its own (silent auto-fill is the
/// deferred automatic-tracking feature); the delivery (a desktop toast / mobile
/// notification) and any resulting log are the platform's / user's decision
/// (golden rule #1 + #4).
class IdleNudge {
  const IdleNudge({
    required this.awayMinutes,
    required this.fromMin,
    required this.toMin,
    required this.coveredSegments,
    required this.message,
  });

  /// Total minutes idle.
  final int awayMinutes;

  /// Wall-clock minute-of-day the away span started / ended, `[0, 1440]`.
  final int fromMin;
  final int toMin;

  /// Planned segments the away span overlapped (in ring order), most-likely
  /// first is [coveredSegments].first — what the user was scheduled to be doing.
  final List<Segment> coveredSegments;

  final String message;

  /// The category to pre-fill a log with, if the user accepts: the segment
  /// active when they went away.
  String? get suggestedCategory =>
      coveredSegments.isEmpty ? null : coveredSegments.first.name;

  @override
  String toString() =>
      'IdleNudge(${awayMinutes}m away, covered ${coveredSegments.length} block(s))';
}

/// Whether the user is idle: [nowEpochMs] is at least [thresholdMinutes] past
/// their [lastActivityEpochMs]. Epoch milliseconds keep this platform-agnostic
/// (the host supplies both from its own idle clock).
bool isIdle({
  required int lastActivityEpochMs,
  required int nowEpochMs,
  required int thresholdMinutes,
}) =>
    nowEpochMs - lastActivityEpochMs >= thresholdMinutes * 60 * 1000;

/// Builds an [IdleNudge] if the user has been idle at least [thresholdMinutes],
/// else null. [profile] is the active ring and [nowMinuteOfDay] is the
/// wall-clock minute the away span ends at (i.e. "now"); the span therefore runs
/// from `nowMinuteOfDay - awayMinutes` to `nowMinuteOfDay`. A span longer than a
/// day is capped at 24h for segment coverage.
IdleNudge? buildIdleNudge({
  required int lastActivityEpochMs,
  required int nowEpochMs,
  required int thresholdMinutes,
  required DayProfile profile,
  required int nowMinuteOfDay,
}) {
  if (!isIdle(
    lastActivityEpochMs: lastActivityEpochMs,
    nowEpochMs: nowEpochMs,
    thresholdMinutes: thresholdMinutes,
  )) {
    return null;
  }
  final awayMinutes = (nowEpochMs - lastActivityEpochMs) ~/ (60 * 1000);
  final now = normalizeMinute(nowMinuteOfDay);
  final capped = awayMinutes.clamp(0, minutesPerDay);
  final fromMin = normalizeMinute(now - capped);

  final covered = _segmentsCovering(profile, fromMin, capped);
  return IdleNudge(
    awayMinutes: awayMinutes,
    fromMin: fromMin,
    toMin: now,
    coveredSegments: covered,
    message: covered.isEmpty
        ? 'You were away for ${formatDuration(awayMinutes)}.'
        : 'You were away for ${formatDuration(awayMinutes)} during '
            '${covered.first.name} — log it, or adjust?',
  );
}

/// Segments overlapped by the clockwise span of [spanMin] minutes starting at
/// [fromMin], in ring order beginning with the segment active at [fromMin].
List<Segment> _segmentsCovering(DayProfile profile, int fromMin, int spanMin) {
  if (spanMin <= 0) return const [];
  final segments = profile.segments;
  final n = segments.length;
  final startIdx = profile.indexAt(fromMin);
  final startSeg = segments[startIdx];

  final out = <Segment>[startSeg];
  // Time left in the start segment past the moment the user went away.
  var remaining = spanMin -
      (startSeg.durationMin - spanMinutes(startSeg.startMin, fromMin));
  var k = 1;
  while (remaining > 0 && k < n) {
    final seg = segments[(startIdx + k) % n];
    out.add(seg);
    remaining -= seg.durationMin;
    k++;
  }
  return out;
}
