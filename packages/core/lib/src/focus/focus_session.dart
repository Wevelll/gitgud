import '../models/time_log.dart';

/// The fields needed to append an actual log — the durable artifact of a focus
/// session (SPEC §12.6). The timer/UI is platform-side; this is the part `core`
/// owns, fed straight into `DayRepository.logActual`.
class PendingLog {
  const PendingLog({
    required this.category,
    required this.startTs,
    required this.endTs,
    this.segmentId,
    this.note,
    this.source = LogSource.timer,
  });

  final String category;
  final String startTs;
  final String endTs;
  final String? segmentId;
  final String? note;
  final LogSource source;

  int get durationMin =>
      DateTime.parse(endTs).difference(DateTime.parse(startTs)).inMinutes;
}

/// A running focus session bound to a category (and optionally the segment it's
/// counted against). On completion it yields a [PendingLog] — a
/// [LogSource.timer] actual — which the caller persists via `logActual`
/// (SPEC §12.6). Holds no timer itself; the elapsed clock is the platform's job.
class FocusSession {
  const FocusSession({
    required this.category,
    required this.startTs,
    this.segmentId,
    this.note,
  });

  final String category;
  final String startTs;
  final String? segmentId;
  final String? note;

  /// The log to append when the session ends at [endTs]. Throws [ArgumentError]
  /// if [endTs] precedes the start.
  PendingLog completeAt(String endTs) {
    if (DateTime.parse(endTs).isBefore(DateTime.parse(startTs))) {
      throw ArgumentError('Focus end ($endTs) precedes start ($startTs)');
    }
    return PendingLog(
      category: category,
      startTs: startTs,
      endTs: endTs,
      segmentId: segmentId,
      note: note,
      source: LogSource.timer,
    );
  }
}

/// A phase of a Pomodoro plan.
enum PomodoroPhase { work, shortBreak, longBreak }

/// One interval of a Pomodoro plan, as minute offsets from the session start.
class PomodoroInterval {
  const PomodoroInterval({
    required this.phase,
    required this.startOffsetMin,
    required this.endOffsetMin,
  });

  final PomodoroPhase phase;
  final int startOffsetMin;
  final int endOffsetMin;

  int get durationMin => endOffsetMin - startOffsetMin;

  @override
  bool operator ==(Object other) =>
      other is PomodoroInterval &&
      other.phase == phase &&
      other.startOffsetMin == startOffsetMin &&
      other.endOffsetMin == endOffsetMin;

  @override
  int get hashCode => Object.hash(phase, startOffsetMin, endOffsetMin);

  @override
  String toString() =>
      'PomodoroInterval(${phase.name}, $startOffsetMin–$endOffsetMin)';
}

/// Builds a classic Pomodoro schedule (SPEC §12.6): [cycles] work intervals of
/// [workMin], each followed by a break — a [longBreakMin] break after every
/// [longBreakEvery]-th work interval (when [longBreakMin] is given), else a
/// [breakMin] short break. The trailing break after the final work interval is
/// omitted. Offsets are minutes from the session start.
List<PomodoroInterval> pomodoroPlan({
  int workMin = 25,
  int breakMin = 5,
  int cycles = 4,
  int? longBreakMin,
  int longBreakEvery = 4,
}) {
  if (workMin < 1 || cycles < 1) {
    throw ArgumentError('workMin and cycles must be >= 1');
  }
  final out = <PomodoroInterval>[];
  var cursor = 0;
  for (var i = 1; i <= cycles; i++) {
    out.add(PomodoroInterval(
      phase: PomodoroPhase.work,
      startOffsetMin: cursor,
      endOffsetMin: cursor + workMin,
    ));
    cursor += workMin;
    if (i == cycles) break; // no break after the last work block
    final isLong = longBreakMin != null && i % longBreakEvery == 0;
    final len = isLong ? longBreakMin : breakMin;
    if (len <= 0) continue;
    out.add(PomodoroInterval(
      phase: isLong ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak,
      startOffsetMin: cursor,
      endOffsetMin: cursor + len,
    ));
    cursor += len;
  }
  return out;
}
