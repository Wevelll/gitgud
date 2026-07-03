import '../time/day_minutes.dart';
import 'day_profile.dart';
import 'segment.dart';

/// Ring-normalized block editing for the dial (SPEC §6.2 add/update/delete),
/// resolved against golden rule #8: the day is always a **gapless ring summing
/// to 1440**.
///
/// Rather than clever wrap/split arithmetic, these operations paint onto a
/// 1440-entry minute-slot array and rebuild runs. It's O(1440) per edit —
/// irrelevant for an occasional user/agent action — and sidesteps the whole
/// family of midnight-wrap and mid-segment-split edge cases by construction.
///
/// Semantics:
/// - [addBlock] overwrites the arc it covers, trimming/splitting whatever was
///   underneath. No gap is created.
/// - [deleteBlock] hands the removed span to its clockwise-preceding neighbor.
/// - [updateBlock] renames/recolors in place, or (when start/end change) moves
///   the block's edges by adjusting the shared boundary with each neighbor.
///
/// Any edit that would leave a segment shorter than [minSegmentMinutes], or
/// collapse the day to a single segment, throws [InvalidProfileException].
extension RingEdit on DayProfile {
  /// Adds a new block [id] spanning `[startMin, endMin)` clockwise, overwriting
  /// whatever it covers.
  DayProfile addBlock({
    required String id,
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    _requireUniqueId(id);
    final start = normalizeMinute(startMin);
    final end = normalizeMinute(endMin);
    final len = start == end ? minutesPerDay : spanMinutes(start, end);
    if (len < minSegmentMinutes || len > minutesPerDay - minSegmentMinutes) {
      throw InvalidProfileException(
        'Block must be $minSegmentMinutes..${minutesPerDay - minSegmentMinutes}'
        ' minutes long (got $len)',
      );
    }
    final slots = _toSlots();
    _paint(slots, start, end, _Owner(id, name, colorHex));
    return _rebuild(slots);
  }

  /// Removes the block [id], handing its span to the segment before it.
  DayProfile deleteBlock(String id) {
    if (segments.length <= 2) {
      throw const InvalidProfileException(
          'Cannot delete: a day needs at least 2 segments');
    }
    final idx = _indexOfId(id);
    final seg = segments[idx];
    final prev = segments[(idx - 1 + segments.length) % segments.length];
    final slots = _toSlots();
    _paint(slots, seg.startMin, seg.endMin,
        _Owner(prev.id, prev.name, prev.colorHex));
    return _rebuild(slots);
  }

  /// Renames/recolors block [id], and/or resizes it by moving its start and/or
  /// end edge. Any omitted field is unchanged.
  ///
  /// Edge moves adjust the boundary shared with the immediate neighbor (the
  /// same math as dragging on the dial), so a shrink hands space to that
  /// neighbor and a grow takes from it — never creating disconnected pieces. An
  /// edge cannot cross past its adjacent segment (that would starve it below the
  /// 15-min minimum); teleporting a block far away is a delete + add, not an
  /// update. Illegal moves throw [InvalidProfileException].
  DayProfile updateBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    final idx = _indexOfId(id);
    final old = segments[idx];

    // Rename / recolor: geometry untouched, so just swap the segment in place.
    var profile = this;
    if (name != null || colorHex != null) {
      final segs = List<Segment>.of(segments);
      segs[idx] = old.copyWith(name: name, colorHex: colorHex);
      profile = DayProfile(
        id: this.id,
        name: this.name,
        segments: segs,
        activeDaysMask: activeDaysMask,
        isDefault: isDefault,
      );
    }
    if (startMin == null && endMin == null) return profile;

    // Move the end edge: the boundary between this block and its next neighbor.
    if (endMin != null) {
      final delta = normalizeMinute(endMin) - old.endMin;
      profile = _moveBoundaryOrThrow(profile, idx, delta, 'end');
    }
    // Move the start edge: the boundary between the previous neighbor and this
    // block. Index is unchanged by the end-edge move above.
    if (startMin != null) {
      final prevIdx = (idx - 1 + segments.length) % segments.length;
      final delta = normalizeMinute(startMin) - old.startMin;
      profile = _moveBoundaryOrThrow(profile, prevIdx, delta, 'start');
    }
    return profile;
  }

  static DayProfile _moveBoundaryOrThrow(
      DayProfile profile, int boundaryIndex, int delta, String edge) {
    if (delta % minutesPerDay == 0) return profile;
    final moved = profile.resizeBoundary(boundaryIndex, delta);
    if (identical(moved, profile)) {
      throw InvalidProfileException(
        'Cannot move $edge edge by $delta: it would cross the adjacent segment '
        'or breach the ${minSegmentMinutes}m minimum',
      );
    }
    return moved;
  }

  int _indexOfId(String id) {
    final i = segments.indexWhere((s) => s.id == id);
    if (i == -1) {
      throw InvalidProfileException('No block with id "$id"');
    }
    return i;
  }

  void _requireUniqueId(String id) {
    if (segments.any((s) => s.id == id)) {
      throw InvalidProfileException('Block id "$id" already exists');
    }
  }

  List<_Owner> _toSlots() {
    final slots = List<_Owner>.filled(minutesPerDay, const _Owner('', '', ''),
        growable: false);
    for (final seg in segments) {
      _paint(slots, seg.startMin, seg.endMin,
          _Owner(seg.id, seg.name, seg.colorHex));
    }
    return slots;
  }

  static void _paint(List<_Owner> slots, int start, int end, _Owner owner) {
    final len = start == end ? minutesPerDay : spanMinutes(start, end);
    for (var k = 0; k < len; k++) {
      slots[(start + k) % minutesPerDay] = owner;
    }
  }

  DayProfile _rebuild(List<_Owner> slots) {
    // Segment starts are minutes whose owner differs from the previous minute.
    final starts = <int>[];
    for (var m = 0; m < minutesPerDay; m++) {
      final prev = slots[(m - 1 + minutesPerDay) % minutesPerDay];
      if (slots[m].id != prev.id) starts.add(m);
    }
    if (starts.length < 2) {
      throw const InvalidProfileException(
          'Edit would collapse the day to a single segment');
    }

    final used = <String>{};
    final rebuilt = <Segment>[];
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = starts[(i + 1) % starts.length];
      final owner = slots[s];
      // A segment split into non-adjacent pieces would reuse an id; keep the
      // first, mint stable suffixes for the rest so ids stay unique.
      var id = owner.id;
      if (!used.add(id)) {
        var n = 2;
        while (!used.add('$id~$n')) {
          n++;
        }
        id = '$id~$n';
      }
      rebuilt.add(Segment(
        id: id,
        name: owner.name,
        colorHex: owner.colorHex,
        startMin: s,
        endMin: e,
      ));
    }

    // The validating constructor enforces contiguity, sum==1440, and the
    // 15-minute minimum — so an edit that starves a neighbor throws here.
    return DayProfile(
      id: id,
      name: name,
      segments: rebuilt,
      activeDaysMask: activeDaysMask,
      isDefault: isDefault,
    );
  }
}

/// Slot owner: the identity + presentation of the segment occupying a minute.
class _Owner {
  const _Owner(this.id, this.name, this.colorHex);
  final String id;
  final String name;
  final String colorHex;
}
