import '../time/day_minutes.dart';
import 'segment.dart';

/// Thrown when a [DayProfile] is constructed or mutated into an invalid ring.
class InvalidProfileException implements Exception {
  const InvalidProfileException(this.message);
  final String message;
  @override
  String toString() => 'InvalidProfileException: $message';
}

/// An upcoming segment paired with how many minutes until it starts.
class UpcomingBlock {
  const UpcomingBlock({required this.segment, required this.inMinutes});
  final Segment segment;
  final int inMinutes;
}

/// A day layout: an ordered, contiguous ring of [Segment]s that tiles the full
/// 24 hours with no gaps or overlaps.
///
/// Invariants (validated on build):
/// - Each segment's `endMin` equals the next segment's `startMin` (shared
///   boundary), the last wrapping around to the first.
/// - Durations sum to exactly 1440 (golden rule #8 — constant per profile).
/// - Every segment is at least [minSegmentMinutes] long.
///
/// Segments are held in clockwise ring order, matching the prototype's cyclic
/// `blocks` list.
class DayProfile {
  DayProfile._({
    required this.id,
    required this.name,
    required this.segments,
    this.activeDaysMask = 0,
    this.isDefault = false,
  });

  /// Validating constructor. Throws [InvalidProfileException] if [segments] do
  /// not form a legal ring.
  factory DayProfile({
    required String id,
    required String name,
    required List<Segment> segments,
    int activeDaysMask = 0,
    bool isDefault = false,
  }) {
    _validate(segments);
    return DayProfile._(
      id: id,
      name: name,
      segments: List.unmodifiable(segments),
      activeDaysMask: activeDaysMask,
      isDefault: isDefault,
    );
  }

  /// Builds a ring from `(startMin, name, colorHex)` triples given in clockwise
  /// order. Each segment's end is the next segment's start (the last wraps to
  /// the first), so the ring is contiguous by construction — the ergonomic way
  /// to author a day, mirroring the prototype's `INITIAL`.
  factory DayProfile.ring({
    required String id,
    required String name,
    required List<({int startMin, String name, String colorHex})> spans,
    List<String>? segmentIds,
    int activeDaysMask = 0,
    bool isDefault = false,
  }) {
    if (spans.length < 2) {
      throw const InvalidProfileException('A ring needs at least 2 segments');
    }
    final segs = <Segment>[];
    for (var i = 0; i < spans.length; i++) {
      final cur = spans[i];
      final next = spans[(i + 1) % spans.length];
      segs.add(Segment(
        id: segmentIds != null ? segmentIds[i] : '$id.seg$i',
        name: cur.name,
        colorHex: cur.colorHex,
        startMin: normalizeMinute(cur.startMin),
        endMin: normalizeMinute(next.startMin),
      ));
    }
    return DayProfile(
      id: id,
      name: name,
      segments: segs,
      activeDaysMask: activeDaysMask,
      isDefault: isDefault,
    );
  }

  final String id;
  final String name;
  final List<Segment> segments;

  /// Bitmask of weekdays this profile is active on (bit 0 = Monday). 0 = unset.
  final int activeDaysMask;
  final bool isDefault;

  static void _validate(List<Segment> segments) {
    if (segments.length < 2) {
      throw const InvalidProfileException(
          'A profile needs at least 2 segments');
    }
    var total = 0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final next = segments[(i + 1) % segments.length];
      if (seg.endMin != next.startMin) {
        throw InvalidProfileException(
          'Gap/overlap: segment ${seg.id} ends at ${seg.endMin} but '
          '${next.id} starts at ${next.startMin}',
        );
      }
      if (seg.durationMin < minSegmentMinutes) {
        throw InvalidProfileException(
          'Segment ${seg.id} is ${seg.durationMin}m (< $minSegmentMinutes)',
        );
      }
      total += seg.durationMin;
    }
    if (total != minutesPerDay) {
      throw InvalidProfileException('Durations sum to $total, not 1440');
    }
  }

  /// Index of the segment containing [minute]. Because the ring is contiguous
  /// and covers the whole day, exactly one segment matches.
  int indexAt(int minute) {
    final m = normalizeMinute(minute);
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].contains(m)) return i;
    }
    // Unreachable for a valid ring, but stay defensive rather than throw.
    return 0;
  }

  /// The segment active at [minute].
  Segment segmentAt(int minute) => segments[indexAt(minute)];

  /// The segment after the one active at [minute] (wraps around the ring).
  Segment nextAfter(int minute) {
    final i = indexAt(minute);
    return segments[(i + 1) % segments.length];
  }

  /// Minutes elapsed within the current segment at [minute].
  int offsetInto(int minute) {
    final seg = segmentAt(minute);
    return spanMinutes(seg.startMin, normalizeMinute(minute));
  }

  /// Minutes remaining in the current segment at [minute].
  int remainingAt(int minute) =>
      segmentAt(minute).durationMin - offsetInto(minute);

  /// The next [count] segments starting strictly after [minute], each paired
  /// with the minutes from [minute] until it begins. Walks clockwise around the
  /// ring; if [count] exceeds the number of segments it wraps into following
  /// days and `inMinutes` keeps accumulating (so day 2's Sleep reads e.g.
  /// 1500, not 60). Powers MCP `list_upcoming`.
  List<UpcomingBlock> upcomingFrom(int minute, int count) {
    final m = normalizeMinute(minute);
    final result = <UpcomingBlock>[];
    var cursorStart = m;
    var elapsed = 0;
    for (var k = 0; k < count; k++) {
      final next = nextAfter(cursorStart);
      final step = spanMinutes(cursorStart, next.startMin);
      elapsed += step == 0 ? minutesPerDay : step;
      result.add(UpcomingBlock(segment: next, inMinutes: elapsed));
      cursorStart = next.startMin;
    }
    return result;
  }

  /// Moves the shared boundary between segment [index] and its clockwise
  /// neighbor by [deltaMin] minutes, shrinking one and growing the other while
  /// their combined duration stays constant. Returns a new [DayProfile], or
  /// `this` unchanged if the move would push either segment below
  /// [minSegmentMinutes] — matching the prototype's `resize` guard.
  DayProfile resizeBoundary(int index, int deltaMin) {
    if (index < 0 || index >= segments.length) {
      throw RangeError.index(index, segments, 'index');
    }
    final i = index;
    final j = (index + 1) % segments.length;
    final segI = segments[i];
    final segJ = segments[j];

    final combined = segI.durationMin + segJ.durationMin;
    final newBoundary = normalizeMinute(segI.endMin + deltaMin);
    final newDurI = spanMinutes(segI.startMin, newBoundary);

    // Reject if either side would fall below the minimum length.
    if (newDurI < minSegmentMinutes || newDurI > combined - minSegmentMinutes) {
      return this;
    }

    final updated = List<Segment>.of(segments);
    updated[i] = segI.copyWith(endMin: newBoundary);
    updated[j] = segJ.copyWith(startMin: newBoundary);
    return DayProfile._(
      id: id,
      name: name,
      segments: List.unmodifiable(updated),
      activeDaysMask: activeDaysMask,
      isDefault: isDefault,
    );
  }

  DayProfile copyWith({
    String? id,
    String? name,
    List<Segment>? segments,
    int? activeDaysMask,
    bool? isDefault,
  }) {
    return DayProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      segments: segments ?? this.segments,
      activeDaysMask: activeDaysMask ?? this.activeDaysMask,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
