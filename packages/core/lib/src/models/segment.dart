import '../time/day_minutes.dart';

/// A single wedge of the day: a named, colored span of time.
///
/// Stored as `startMin`/`endMin` (minutes since midnight) to match the SQLite
/// schema (SPEC §5). A segment **wraps midnight** when `endMin < startMin`
/// (e.g. Sleep 23:00–07:00 → start 1380, end 420) — golden rule #8. Duration is
/// always computed via clockwise span so the wrap case needs no special-casing
/// at call sites.
class Segment {
  const Segment({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.startMin,
    required this.endMin,
  });

  final String id;
  final String name;

  /// Color as a hex string, e.g. `#4B4FA6`. `core` is platform-agnostic, so we
  /// never hold a Flutter `Color` here — the UI parses this.
  final String colorHex;

  /// Start, minutes since midnight, `[0, 1440)`.
  final int startMin;

  /// End, minutes since midnight, `[0, 1440)`. May be `< startMin` (wraps).
  final int endMin;

  /// Clockwise duration in minutes. When `startMin == endMin` the segment fills
  /// the whole day (1440) rather than being zero-length — a single-segment
  /// profile is legitimate; a zero-length one is not (enforced elsewhere).
  int get durationMin =>
      startMin == endMin ? minutesPerDay : spanMinutes(startMin, endMin);

  /// True if this segment crosses midnight.
  bool get wrapsMidnight => endMin < startMin;

  /// True if [minute] falls inside this segment (start-inclusive, end-exclusive),
  /// correctly handling the midnight wrap.
  bool contains(int minute) =>
      spanMinutes(startMin, normalizeMinute(minute)) < durationMin;

  Segment copyWith({
    String? id,
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    return Segment(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Segment &&
      other.id == id &&
      other.name == name &&
      other.colorHex == colorHex &&
      other.startMin == startMin &&
      other.endMin == endMin;

  @override
  int get hashCode => Object.hash(id, name, colorHex, startMin, endMin);

  @override
  String toString() => 'Segment($id, "$name", ${formatMinuteOfDay(startMin)}–'
      '${formatMinuteOfDay(endMin)})';
}
