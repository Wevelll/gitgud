import '../models/day_profile.dart';
import '../models/segment.dart';

/// A pending block-transition notification: the block about to start, how many
/// minutes from the reference time until it fires, and the message to show.
///
/// Pure data produced by [transitionAlerts]; the UI layer turns these into
/// scheduled OS / browser notifications (golden rule #1 — the schedule is core
/// logic, delivery is the platform's job).
class TransitionAlert {
  const TransitionAlert({
    required this.minutesUntil,
    required this.block,
    required this.message,
  });

  /// Minutes from the reference time ("now") until this alert should fire.
  final int minutesUntil;

  /// The block that is starting.
  final Segment block;

  /// Human-readable message, e.g. "Deep work starts now".
  final String message;

  @override
  bool operator ==(Object other) =>
      other is TransitionAlert &&
      other.minutesUntil == minutesUntil &&
      other.block == block &&
      other.message == message;

  @override
  int get hashCode => Object.hash(minutesUntil, block, message);

  @override
  String toString() => 'TransitionAlert(+$minutesUntil, ${block.name})';
}

/// The upcoming block-transition alerts for [profile], starting from [fromMin]
/// (minutes since midnight). Returns up to [count] alerts, each firing
/// [leadMinutes] before its block begins (0 = right at the transition).
///
/// Built on [DayProfile.upcomingFrom], so midnight wrap and day-rollover are
/// already handled: `minutesUntil` accumulates forward from [fromMin].
List<TransitionAlert> transitionAlerts(
  DayProfile profile, {
  required int fromMin,
  int count = 3,
  int leadMinutes = 0,
}) {
  return [
    for (final u in profile.upcomingFrom(fromMin, count))
      TransitionAlert(
        // A lead longer than the gap means "fire now" rather than in the past.
        minutesUntil: (u.inMinutes - leadMinutes).clamp(0, 1 << 31),
        block: u.segment,
        message: leadMinutes <= 0
            ? '${u.segment.name} starts now'
            : '${u.segment.name} starts in $leadMinutes min',
      ),
  ];
}
