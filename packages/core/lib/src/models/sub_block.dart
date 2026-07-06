/// Sub-blocks are the finer detail *inside* a top-level [Segment] (SPEC §2 —
/// the day reads coarse from a distance, but the active/tapped block unfolds
/// into the tasks planned within it). A sub-block is itself just "a named,
/// colored span", so we reuse [Segment] as the value type rather than minting a
/// parallel one — its [Segment.contains]/[Segment.durationMin] are already
/// midnight-wrap-aware (golden rule #8).
///
/// Unlike the top-level ring (which must tile 24h with no gaps — see
/// [DayProfile]), sub-blocks are **sparse**: they need not cover the parent,
/// but each must lie *within* it and siblings must not overlap. That different
/// invariant is exactly why these live outside the ring's tiling validation.
library;

import '../time/day_minutes.dart';
import 'day_profile.dart';
import 'segment.dart';

/// Thrown when a set of sub-blocks is not a legal layout for its parent segment.
class InvalidSubBlockException implements Exception {
  const InvalidSubBlockException(this.message);
  final String message;
  @override
  String toString() => 'InvalidSubBlockException: $message';
}

/// Clockwise offset of [minute] from [parent]'s start, in `[0, durationMin]`.
/// Because everything is measured as a forward offset from the parent start,
/// the parent's own midnight wrap needs no special-casing.
int offsetInParent(Segment parent, int minute) =>
    spanMinutes(parent.startMin, normalizeMinute(minute));

/// Whether [child]'s whole clockwise span lies within [parent]'s span.
///
/// Reduces both to offsets from the parent start: the child fits iff it starts
/// inside the parent and ends no later than the parent's end. Works when the
/// parent wraps midnight (e.g. a Sleep 23:00–07:00 parent holding a 01:00–02:00
/// child) and when the child itself straddles midnight inside such a parent.
bool parentContainsSubBlock(Segment parent, Segment child) {
  final startOffset = spanMinutes(parent.startMin, child.startMin);
  // A child that starts exactly at the parent end (offset == duration) is out.
  if (startOffset >= parent.durationMin) return false;
  return startOffset + child.durationMin <= parent.durationMin;
}

/// Validates that [children] form a legal sparse layout inside [parent]:
/// unique ids, each with a real (non-zero, non-full-day) length, each contained
/// in the parent, and no two overlapping. Gaps between them are allowed.
///
/// Throws [InvalidSubBlockException] on the first violation. There is no minimum
/// sub-block length (a deliberate product choice — sub-blocks can be as fine as
/// a task needs).
void validateSubBlocks(Segment parent, List<Segment> children) {
  final seenIds = <String>{};
  for (final c in children) {
    if (!seenIds.add(c.id)) {
      throw InvalidSubBlockException('Duplicate sub-block id "${c.id}"');
    }
    // start == end means "fills the whole day" per Segment.durationMin — never
    // a valid sub-block of a proper (< 24h) parent.
    if (c.startMin == c.endMin) {
      throw InvalidSubBlockException(
        'Sub-block "${c.id}" has zero / full-day length',
      );
    }
    if (!parentContainsSubBlock(parent, c)) {
      throw InvalidSubBlockException(
        'Sub-block "${c.id}" (${formatMinuteOfDay(c.startMin)}–'
        '${formatMinuteOfDay(c.endMin)}) is not within parent "${parent.id}" '
        '(${formatMinuteOfDay(parent.startMin)}–'
        '${formatMinuteOfDay(parent.endMin)})',
      );
    }
  }

  // Non-overlap: because every child lies within the parent (checked above),
  // each maps to a plain linear interval [offset, offset + duration] in
  // `[0, parent.durationMin]`. Sort by offset and check neighbours are disjoint.
  final sorted = sortedInParent(parent, children);
  for (var i = 1; i < sorted.length; i++) {
    final prev = sorted[i - 1];
    final cur = sorted[i];
    final prevEnd =
        spanMinutes(parent.startMin, prev.startMin) + prev.durationMin;
    final curStart = spanMinutes(parent.startMin, cur.startMin);
    if (curStart < prevEnd) {
      throw InvalidSubBlockException(
        'Sub-blocks "${prev.id}" and "${cur.id}" overlap',
      );
    }
  }
}

/// [children] ordered by their clockwise start offset within [parent] — the
/// order they appear as you sweep the parent's arc (the render order).
List<Segment> sortedInParent(Segment parent, List<Segment> children) {
  final list = [...children];
  list.sort((a, b) => spanMinutes(parent.startMin, a.startMin)
      .compareTo(spanMinutes(parent.startMin, b.startMin)));
  return list;
}

/// The sub-block covering [minute], or null if [minute] falls in a gap. Assumes
/// [children] are valid for [parent] (non-overlapping), so at most one matches.
Segment? activeSubBlockAt(Segment parent, List<Segment> children, int minute) {
  final m = normalizeMinute(minute);
  for (final c in children) {
    if (c.contains(m)) return c;
  }
  return null;
}

/// Trims [child] to lie within [parent], returning the clipped sub-block, or
/// null if they no longer overlap at all. Preserves the child's id/name/color.
///
/// This is the "clip" cascade (the chosen policy): when a parent block is
/// resized smaller, a sub-block that now overhangs is shortened to the parent's
/// edge rather than dropped whole or blocking the resize.
///
/// Works on the circle by unrolling from the parent start: a child that now
/// starts *before* the parent maps to a negative offset, and the overlap is the
/// intersection of `[childStart, childEnd)` with `[0, parentDuration)`.
Segment? clipToParent(Segment parent, Segment child) {
  final pDur = parent.durationMin;
  var cs = spanMinutes(parent.startMin, child.startMin);
  // An offset past the parent's end reads as "started before the parent" —
  // treat it as negative so the intersection below is a plain linear clamp.
  if (cs > pDur) cs -= minutesPerDay;
  final ce = cs + child.durationMin;

  final lo = cs < 0 ? 0 : cs;
  final hi = ce > pDur ? pDur : ce;
  if (hi <= lo) return null; // no overlap left

  return child.copyWith(
    startMin: normalizeMinute(parent.startMin + lo),
    endMin: normalizeMinute(parent.startMin + hi),
  );
}

/// Re-fits [plan] after a profile's segments changed (a block was resized,
/// deleted, or overwritten): drops sub-blocks whose parent segment no longer
/// exists, and clips the rest to their parent's current span (dropping any that
/// no longer overlap). Keeps the store's overlay valid after every ring edit.
Map<String, List<Segment>> reconcileSubBlocks(
  DayProfile profile,
  Map<String, List<Segment>> plan,
) {
  final byId = {for (final s in profile.segments) s.id: s};
  final out = <String, List<Segment>>{};
  for (final entry in plan.entries) {
    final parent = byId[entry.key];
    if (parent == null) continue; // parent gone → its sub-blocks go too
    final kept = <Segment>[
      for (final child in entry.value)
        if (clipToParent(parent, child) case final c?) c,
    ];
    if (kept.isNotEmpty) out[entry.key] = kept;
  }
  return out;
}

/// The sparse sub-block overlay for a day: parent-segment id → its sub-blocks.
///
/// Kept separate from [DayProfile] on purpose — the profile owns the gapless
/// 24h ring; this owns the optional, sparse detail painted inside it. They are
/// validated together via [validateAgainst] but stored and edited independently,
/// so the ring's tiling invariant stays untouched.
class SubBlockPlan {
  SubBlockPlan(Map<String, List<Segment>> byParent)
      : _byParent = {
          for (final e in byParent.entries)
            e.key: List<Segment>.unmodifiable(e.value),
        };

  const SubBlockPlan.empty() : _byParent = const {};

  final Map<String, List<Segment>> _byParent;

  /// Parent ids that have at least one sub-block.
  Iterable<String> get parentIds => _byParent.keys;

  /// The sub-blocks planned inside [segmentId] (empty if none).
  List<Segment> of(String segmentId) => _byParent[segmentId] ?? const [];

  bool get isEmpty => _byParent.isEmpty;

  /// Validates the whole overlay against [profile]: every keyed parent must be a
  /// real segment, and each parent's sub-blocks must be legal (see
  /// [validateSubBlocks]). Throws [InvalidSubBlockException] on violation.
  void validateAgainst(DayProfile profile) {
    for (final entry in _byParent.entries) {
      final matches = profile.segments.where((s) => s.id == entry.key);
      if (matches.isEmpty) {
        throw InvalidSubBlockException(
          'Sub-blocks reference unknown parent segment "${entry.key}"',
        );
      }
      validateSubBlocks(matches.first, entry.value);
    }
  }

  /// The (parent, active sub-block?) at [minute]: the coarse block you're in,
  /// plus the finer piece within it (or null when the minute is in a gap). This
  /// is what the hub readout and the painter's reveal use.
  ({Segment parent, Segment? child}) contextAt(DayProfile profile, int minute) {
    final parent = profile.segmentAt(minute);
    final child = activeSubBlockAt(parent, of(parent.id), minute);
    return (parent: parent, child: child);
  }

  @override
  bool operator ==(Object other) {
    if (other is! SubBlockPlan) return false;
    if (_byParent.length != other._byParent.length) return false;
    for (final e in _byParent.entries) {
      final o = other._byParent[e.key];
      if (o == null || o.length != e.value.length) return false;
      for (var i = 0; i < e.value.length; i++) {
        if (e.value[i] != o[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(_byParent.keys);
}
