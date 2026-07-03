import '../time/civil_date.dart';

/// How an actual time log was recorded (SPEC §4).
enum LogSource { manual, timer, agent }

/// An append-only record of what actually happened (SPEC §4/§5 `time_logs`).
///
/// Start/end are ISO-8601 **timestamps** (instants), so a log that crosses
/// midnight has a duration that just works — no minute-of-day wrap math needed
/// here. [date] is the civil day the log is attributed to (usually the start's
/// local date).
class TimeLog {
  TimeLog({
    required this.id,
    required this.date,
    required this.startTs,
    required this.endTs,
    required this.category,
    this.segmentId,
    this.note,
    this.source = LogSource.manual,
  })  : start = DateTime.parse(startTs),
        end = DateTime.parse(endTs) {
    if (end.isBefore(start)) {
      throw ArgumentError('TimeLog end ($endTs) precedes start ($startTs)');
    }
  }

  final String id;
  final CivilDate date;
  final String startTs;
  final String endTs;
  final String category;

  /// The planned segment this actual maps to, if any.
  final String? segmentId;
  final String? note;
  final LogSource source;

  /// Parsed instants (from [startTs]/[endTs]).
  final DateTime start;
  final DateTime end;

  /// Elapsed minutes, always >= 0 (validated on construction).
  int get durationMin => end.difference(start).inMinutes;

  @override
  bool operator ==(Object other) =>
      other is TimeLog &&
      other.id == id &&
      other.date == date &&
      other.startTs == startTs &&
      other.endTs == endTs &&
      other.category == category &&
      other.segmentId == segmentId &&
      other.note == note &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(id, date, startTs, endTs, category, segmentId, note, source);
}
