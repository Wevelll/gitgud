import '../time/day_minutes.dart';
import 'day_profile.dart';
import 'segment.dart';

/// Hit-testing the ring in *time*, not pixels — what "the user grabbed this
/// boundary" means once a tap has been reduced to a minute of the day.
///
/// The widget converts a touch position into a minute (pure geometry) and this
/// decides what that minute means for the day's model. Keeping it here means
/// the wrap-around case — a boundary at 00:00 grabbed from 23:52 — is handled
/// by [spanMinutes] like everywhere else, instead of being re-derived in the
/// widget tree (golden rules #1 and #8).
extension RingHit on DayProfile {
  /// The segment whose **end** boundary lies closest to [minute], or null if
  /// the nearest one is further than [toleranceMin] away.
  ///
  /// Every boundary is one segment's end and the next segment's start; naming
  /// it by the ending segment matches how an edit is expressed
  /// (`updateBlock(id, endMin: …)`).
  ///
  /// A tolerance wider than the shortest segment could make a grab ambiguous,
  /// so the nearest boundary always wins ties by scan order — deterministic,
  /// and in practice the caller's tolerance is far smaller than a wedge.
  Segment? boundaryNear(int minute, {int toleranceMin = 18}) {
    Segment? best;
    var bestDistance = toleranceMin + 1;
    for (final seg in segments) {
      final distance = boundaryDistance(seg.endMin, minute);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = seg;
      }
    }
    return bestDistance <= toleranceMin ? best : null;
  }
}

/// Distance in minutes between two points on the 24-hour ring, the short way
/// round: `boundaryDistance(0, 1435)` is 5, not 1435.
int boundaryDistance(int a, int b) {
  final forward = spanMinutes(a, b);
  return forward <= minutesPerDay - forward ? forward : minutesPerDay - forward;
}

/// Rounds [minute] to the nearest multiple of [stepMin] on the ring, so a drag
/// lands on a tidy time instead of wherever the finger happened to be.
/// Wrap-safe: 1438 with a 5-minute step snaps to 0, not 1440.
int snapMinute(int minute, {int stepMin = 5}) =>
    normalizeMinute(((normalizeMinute(minute) / stepMin).round() * stepMin));
