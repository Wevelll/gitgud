import 'dart:math' as math;

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// How the dial renders time (SPEC §2.2).
enum DialMode {
  /// The signature mode: the whole day-disc rotates so *now* stays pinned to
  /// the fixed top marker.
  compass,

  /// Familiar mode: the disc is static (midnight at top) and a hand sweeps.
  clock,
}

/// Parses a `#RRGGBB` (or `#AARRGGBB`) hex string into a [Color]. Colour lives
/// in the UI, never in `core` (which is platform-agnostic and holds only the
/// hex string).
Color parseHexColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

/// Where things sit on the dial, and how a point on screen maps back to a
/// minute of the day.
///
/// The painter draws with these radii and the gesture layer hit-tests against
/// them, so they live in one place — a handle you can see but not grab (or the
/// reverse) is exactly the bug this prevents. Radii are in the prototype's
/// 360×360 reference frame and scaled by [scale] at paint time.
///
/// This is *pixel* geometry only. What a minute then means for the day —
/// which boundary was grabbed, where it may move — is `core`'s job
/// (`RingHit`, `RingEdit`), per golden rule #1.
class DialGeometry {
  const DialGeometry({
    required this.size,
    required this.mode,
    required this.nowMin,
  });

  /// The square the dial is painted into.
  final Size size;
  final DialMode mode;
  final int nowMin;

  /// Reference radii (the prototype's 360×360 frame).
  static const double ringOuter = 150.0;
  static const double ringInner = 96.0;
  static const double labelRadius = 123.0;
  static const double hubRadius = 82.0;
  static const double referenceSide = 360.0;

  Offset get center => size.center(Offset.zero);

  /// Reference-frame → paint-frame scale factor.
  double get scale => size.shortestSide / referenceSide;

  /// How far the day-disc is rotated: in compass mode it turns backwards by
  /// the current time so *now* stays pinned to the fixed top marker; in clock
  /// mode the disc is still (SPEC §2.2).
  double get discRotationDeg =>
      mode == DialMode.compass ? -(nowMin / 1440.0 * 360.0) : 0.0;

  /// The paint-frame point at reference radius [r], [aDeg] clockwise from 12
  /// o'clock, in **disc** coordinates (before the disc rotation is applied).
  Offset pointAt(double r, double aDeg) {
    final rad = aDeg * math.pi / 180.0;
    return center +
        Offset(r * scale * math.sin(rad), -r * scale * math.cos(rad));
  }

  /// The minute of the day under [local] (a position in the painted box),
  /// undoing the disc rotation so the same math serves both modes.
  int minuteAt(Offset local) {
    final v = local - center;
    final screenDeg = (math.atan2(v.dx, -v.dy) * 180 / math.pi) % 360;
    final discDeg = (screenDeg - discRotationDeg) % 360;
    return ((discDeg / 360.0) * 1440).round() % 1440;
  }

  /// Whether [local] falls in the band where the wedges are drawn — with a
  /// little slop, since a fingertip is bigger than a ring is thick.
  bool isOnRing(Offset local, {double slop = 16}) {
    final r = (local - center).distance / scale;
    return r >= ringInner - slop && r <= ringOuter + slop;
  }
}

/// Renders the 24-hour dial from a [DayProfile] — both compass and clock modes.
/// Geometry is ported from the React prototype (`dial_example.jsx`) and scaled
/// to the paint [Size] so it stays crisp at any resolution.
///
/// The dial is a thin client: it reads current/next/remaining straight from
/// `core` and never does time math itself.
class DialPainter extends CustomPainter {
  DialPainter({
    required this.profile,
    required this.nowMin,
    required this.mode,
    required this.palette,
    this.selectedSegmentId,
    this.actuals = const [],
    this.overlay = const [],
    this.subBlocks = const SubBlockPlan.empty(),
    this.showHandles = false,
    this.draggingBoundaryId,
  });

  final DayProfile profile;
  final int nowMin;
  final DialMode mode;
  final DialPalette palette;
  final String? selectedSegmentId;

  /// Logged actuals for the day, drawn as a thin inner ring against the plan.
  final List<ActualArc> actuals;

  /// Read-only calendar events (SPEC §2.5/§12.1), drawn as thin arcs on a
  /// concentric track just outside the wedge ring — a layer *above* the plan,
  /// never a segment. Overlapping events are pre-assigned to [OverlayArc.track]
  /// lanes (by `overlayFor` in core).
  final List<OverlayArc> overlay;

  /// Sparse sub-block overlay. A segment "reveals" its sub-blocks — its wedge
  /// subdivides in place into them — when it's the active (now) block or the
  /// selected one (SPEC §2: coarse from a distance, detailed when it comes by).
  final SubBlockPlan subBlocks;

  /// Whether to mark the shared boundaries as grabbable (SPEC §2.4). Off for a
  /// read-only dial, so a glanceable snapshot isn't cluttered with affordances
  /// that do nothing.
  final bool showHandles;

  /// The segment whose end boundary is being dragged right now, named the same
  /// way an edit is: by the block that *ends* there.
  final String? draggingBoundaryId;

  /// Whether [seg] should show its sub-blocks: it's active or tapped-selected.
  bool _revealed(Segment seg) =>
      seg.id == selectedSegmentId || seg.contains(nowMin);

  // Reference radii (prototype's 360×360 frame); scaled by `f` at paint time.
  static const _ro = DialGeometry.ringOuter; // segment outer
  static const _ri = DialGeometry.ringInner; // segment inner
  static const _rl = DialGeometry.labelRadius; // label radius
  static const _hub = DialGeometry.hubRadius; // center hub
  static const _actIn = 84.0; // actual-ring inner
  static const _actOut = 93.0; // actual-ring outer
  static const _tickIn = 152.0;
  static const _tickOut = 160.0;
  static const _tickMaj = 167.0;
  static const _numR = 176.0;
  static const _plate = _ro + 12.0;

  double _timeAngleDeg(int min) => min / 1440.0 * 360.0;
  static double _rad(double deg) => deg * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final f = size.shortestSide / 360.0;

    Offset pt(double r, double aDeg) =>
        center +
        Offset(r * f * math.sin(_rad(aDeg)), -r * f * math.cos(_rad(aDeg)));

    // Backing plate.
    canvas.drawCircle(center, _plate * f, Paint()..color = palette.plate);
    canvas.drawCircle(
      center,
      _plate * f,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.plateStroke,
    );

    final thetaDeg = mode == DialMode.compass ? -_timeAngleDeg(nowMin) : 0.0;

    // ---- rotating day-disc ----
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_rad(thetaDeg));
    canvas.translate(-center.dx, -center.dy);

    _drawWedges(canvas, f, pt);
    _drawActuals(canvas, f, pt);
    _drawTicks(canvas, pt);
    _drawOverlay(canvas, f, pt);
    _drawLabels(canvas, thetaDeg, pt);
    _drawNumerals(canvas, thetaDeg, pt);
    _drawBoundaryHandles(canvas, f, thetaDeg, pt);

    canvas.restore();

    // ---- fixed hub + now indicator ----
    _drawHub(canvas, center, f);
    _drawNowIndicator(canvas, center, f, pt);
  }

  void _drawWedges(
    Canvas canvas,
    double f,
    Offset Function(double, double) pt,
  ) {
    for (final seg in profile.segments) {
      final a0 = _timeAngleDeg(seg.startMin);
      final sweep = _timeAngleDeg(seg.durationMin);
      final a1 = a0 + sweep;
      final selected = seg.id == selectedSegmentId;
      final path = _ringSector(pt, a0, a1, _ri, _ro, f, sweep);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = parseHexColor(
            seg.colorHex,
          ).withValues(alpha: selected ? 1.0 : 0.9),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.5
          ..color = selected ? palette.selectedStroke : palette.wedgeStroke,
      );

      // Subdivide-in-place: overlay this block's sub-blocks over the parent
      // colour at the same radii, so unplanned gaps show through as the parent.
      if (_revealed(seg)) {
        for (final sub in subBlocks.of(seg.id)) {
          final subSweep = _timeAngleDeg(sub.durationMin);
          final s0 = _timeAngleDeg(sub.startMin);
          final subPath = _ringSector(
            pt,
            s0,
            s0 + subSweep,
            _ri,
            _ro,
            f,
            subSweep,
          );
          canvas.drawPath(
            subPath,
            Paint()
              ..style = PaintingStyle.fill
              ..color = parseHexColor(sub.colorHex),
          );
          canvas.drawPath(
            subPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = palette.wedgeStroke,
          );
        }
      }
    }
  }

  /// A ring sector from [a0] to [a1] between reference radii [rInU]..[rOutU].
  /// [pt] scales reference radii by [f]; arc radii are scaled to match.
  Path _ringSector(
    Offset Function(double, double) pt,
    double a0,
    double a1,
    double rInU,
    double rOutU,
    double f,
    double sweepDeg,
  ) {
    final large = sweepDeg > 180;
    final ro = Radius.circular(rOutU * f);
    final ri = Radius.circular(rInU * f);
    final o0 = pt(rOutU, a0);
    final o1 = pt(rOutU, a1);
    final i1 = pt(rInU, a1);
    final i0 = pt(rInU, a0);
    return Path()
      ..moveTo(o0.dx, o0.dy)
      ..arcToPoint(o1, radius: ro, largeArc: large, clockwise: true)
      ..lineTo(i1.dx, i1.dy)
      ..arcToPoint(i0, radius: ri, largeArc: large, clockwise: false)
      ..close();
  }

  /// Draws logged actuals as a thin ring just inside the planned wedges — the
  /// "what really happened" band against "what was planned".
  void _drawActuals(
    Canvas canvas,
    double f,
    Offset Function(double, double) pt,
  ) {
    if (actuals.isEmpty) return;
    // Faint track so the band reads as a ring even where nothing is logged.
    canvas.drawPath(
      _ringSector(pt, 0, 359.99, _actIn, _actOut, f, 359.99),
      Paint()
        ..style = PaintingStyle.fill
        ..color = palette.wedgeStroke.withValues(alpha: 0.5),
    );
    for (final a in actuals) {
      final sweep = _timeAngleDeg((a.endMin - a.startMin) % 1440);
      if (sweep <= 0) continue;
      final a0 = _timeAngleDeg(a.startMin);
      canvas.drawPath(
        _ringSector(pt, a0, a0 + sweep, _actIn, _actOut, f, sweep),
        Paint()
          ..style = PaintingStyle.fill
          ..color = parseHexColor(a.colorHex).withValues(alpha: 0.95),
      );
    }
  }

  // Calendar-overlay track geometry (reference units, scaled by `f`). Sits just
  // outside the wedge ring; overlapping events step outward one lane at a time.
  static const _ovBase = 152.5; // first lane inner radius
  static const _ovThick = 3.5; // arc thickness
  static const _ovStep = 5.0; // lane-to-lane spacing
  static const _ovMaxTrack = 3; // beyond this, clamp so we stay inside numerals

  /// Draws read-only calendar events as thin arcs on concentric lanes just
  /// outside the wedges (SPEC §2.5). Rounded caps so short meetings read as pills
  /// rather than hairlines.
  void _drawOverlay(
    Canvas canvas,
    double f,
    Offset Function(double, double) pt,
  ) {
    if (overlay.isEmpty) return;
    for (final ev in overlay) {
      final sweep = _timeAngleDeg((ev.endMin - ev.startMin).clamp(0, 1440));
      if (sweep <= 0) continue;
      final track = ev.track > _ovMaxTrack ? _ovMaxTrack : ev.track;
      final rIn = _ovBase + track * _ovStep;
      final a0 = _timeAngleDeg(ev.startMin);
      canvas.drawPath(
        _ringSector(pt, a0, a0 + sweep, rIn, rIn + _ovThick, f, sweep),
        Paint()
          ..style = PaintingStyle.fill
          ..color = parseHexColor(ev.colorHex).withValues(alpha: 0.92),
      );
    }
  }

  /// Marks each shared boundary as something you can grab and drag (SPEC §2.4).
  ///
  /// Drawn inside the rotating disc so a handle stays on its boundary in
  /// compass mode; the time readout on the one being dragged is counter-rotated
  /// like every other label (golden rule #9).
  void _drawBoundaryHandles(
    Canvas canvas,
    double f,
    double thetaDeg,
    Offset Function(double, double) pt,
  ) {
    if (!showHandles) return;
    for (final seg in profile.segments) {
      final dragging = seg.id == draggingBoundaryId;
      final a = _timeAngleDeg(seg.endMin);
      canvas.drawLine(
        pt(_ri - 2, a),
        pt(_ro + 2, a),
        Paint()
          ..strokeWidth = dragging ? 3 : 1.5
          ..strokeCap = StrokeCap.round
          ..color = dragging
              ? palette.marker
              : palette.marker.withValues(alpha: 0.35),
      );
      // A knob, so the boundary reads as a grip rather than a hairline.
      canvas.drawCircle(
        pt((_ri + _ro) / 2, a),
        (dragging ? 5.5 : 3.5) * f,
        Paint()
          ..color = dragging
              ? palette.marker
              : palette.marker.withValues(alpha: 0.45),
      );
      if (dragging) {
        _drawUprightText(
          canvas,
          pt(_ro + 22, a),
          thetaDeg,
          formatMinuteOfDay(seg.endMin),
          TextStyle(
            color: palette.label,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      }
    }
  }

  void _drawTicks(Canvas canvas, Offset Function(double, double) pt) {
    for (var h = 0; h < 24; h++) {
      final a = h * 15.0;
      final maj = h % 6 == 0;
      canvas.drawLine(
        pt(_tickIn, a),
        pt(maj ? _tickMaj : _tickOut, a),
        Paint()
          ..strokeWidth = maj ? 1.6 : 1.0
          ..color = maj ? palette.tickMajor : palette.tickMinor,
      );
    }
  }

  void _drawLabels(
    Canvas canvas,
    double thetaDeg,
    Offset Function(double, double) pt,
  ) {
    for (final seg in profile.segments) {
      // When a block is revealed and subdivided, label its sub-blocks instead
      // of the parent (the parent colour is now just the gaps).
      final subs = _revealed(seg) ? subBlocks.of(seg.id) : const <Segment>[];
      if (subs.isNotEmpty) {
        for (final sub in subs) {
          if (sub.durationMin < 45) continue; // no room on thin sub-blocks
          final am =
              _timeAngleDeg(sub.startMin) + _timeAngleDeg(sub.durationMin) / 2;
          _drawUprightText(
            canvas,
            pt(_rl, am),
            thetaDeg,
            sub.name,
            TextStyle(
              color: palette.label,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          );
        }
        continue;
      }

      final sweep = _timeAngleDeg(seg.durationMin);
      if (seg.durationMin < 55) continue; // hide labels on thin wedges
      final am = _timeAngleDeg(seg.startMin) + sweep / 2;
      _drawUprightText(
        canvas,
        pt(_rl, am),
        thetaDeg,
        seg.name,
        TextStyle(
          color: palette.label,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }

  void _drawNumerals(
    Canvas canvas,
    double thetaDeg,
    Offset Function(double, double) pt,
  ) {
    for (final h in const [0, 3, 6, 9, 12, 15, 18, 21]) {
      final a = h * 15.0;
      _drawUprightText(
        canvas,
        pt(_numR, a),
        thetaDeg,
        h.toString().padLeft(2, '0'),
        TextStyle(
          color: palette.numeral,
          fontSize: 10,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
  }

  /// Draws [text] centered at [at], counter-rotated by `-thetaDeg` so it stays
  /// upright even though the disc is rotated (golden rule #9).
  void _drawUprightText(
    Canvas canvas,
    Offset at,
    double thetaDeg,
    String text,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(_rad(-thetaDeg));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _drawHub(Canvas canvas, Offset center, double f) {
    canvas.drawCircle(center, _hub * f, Paint()..color = palette.hub);
    canvas.drawCircle(
      center,
      _hub * f,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.plateStroke,
    );

    final cur = profile.segmentAt(nowMin);
    final remaining = profile.remainingAt(nowMin);
    final next = profile.nextAfter(nowMin);
    // The finer sub-block you're inside right now (if the block has detail).
    final detail = activeSubBlockAt(cur, subBlocks.of(cur.id), nowMin);

    _hubText(
      canvas,
      center,
      -22 * f,
      detail == null ? 'NOW' : 'NOW · ${detail.name}',
      TextStyle(color: palette.hubMuted, fontSize: 10 * f, letterSpacing: 1.5),
    );
    _hubText(
      canvas,
      center,
      -4 * f,
      cur.name,
      TextStyle(
        color: palette.label,
        fontSize: 15 * f,
        fontWeight: FontWeight.w700,
      ),
    );
    _hubText(
      canvas,
      center,
      20 * f,
      '${formatDuration(remaining)} left',
      TextStyle(
        color: parseHexColor(cur.colorHex),
        fontSize: 19 * f,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    _hubText(
      canvas,
      center,
      40 * f,
      'next · ${next.name} at ${formatMinuteOfDay(next.startMin)}',
      TextStyle(color: palette.hubMuted, fontSize: 9.5 * f),
    );
  }

  void _hubText(
    Canvas canvas,
    Offset center,
    double dy,
    String text,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy + dy - tp.height / 2),
    );
  }

  void _drawNowIndicator(
    Canvas canvas,
    Offset center,
    double f,
    Offset Function(double, double) pt,
  ) {
    final paint = Paint()..color = palette.marker;
    if (mode == DialMode.compass) {
      // Fixed downward triangle at the top.
      final tip = pt(_ro - 4, 0);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(center.dx - 8 * f, center.dy - (_ro + 12) * f)
        ..lineTo(center.dx + 8 * f, center.dy - (_ro + 12) * f)
        ..close();
      canvas.drawPath(path, paint);
    } else {
      final hand = pt(_ro - 4, _timeAngleDeg(nowMin));
      canvas.drawLine(
        center,
        hand,
        Paint()
          ..color = palette.marker
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(center, 4 * f, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DialPainter old) =>
      old.nowMin != nowMin ||
      old.mode != mode ||
      old.profile != profile ||
      old.selectedSegmentId != selectedSegmentId ||
      old.palette != palette ||
      old.subBlocks != subBlocks ||
      !listEquals(old.actuals, actuals) ||
      !listEquals(old.overlay, overlay) ||
      old.showHandles != showHandles ||
      old.draggingBoundaryId != draggingBoundaryId;
}

/// A logged actual placed on the dial: a `[startMin, endMin)` arc (minutes since
/// midnight, may wrap) in the category's color, drawn on the inner ring.
class ActualArc {
  const ActualArc({
    required this.startMin,
    required this.endMin,
    required this.colorHex,
  });

  final int startMin;
  final int endMin;
  final String colorHex;

  @override
  bool operator ==(Object other) =>
      other is ActualArc &&
      other.startMin == startMin &&
      other.endMin == endMin &&
      other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(startMin, endMin, colorHex);
}

/// A read-only calendar event placed on the dial: a `[startMin, endMin)` arc
/// (already clipped to the day, so it never wraps) on lane [track], in its
/// calendar's color. Built from a core `OverlayEvent` by the screen.
class OverlayArc {
  const OverlayArc({
    required this.startMin,
    required this.endMin,
    required this.track,
    required this.colorHex,
  });

  final int startMin;
  final int endMin;
  final int track;
  final String colorHex;

  @override
  bool operator ==(Object other) =>
      other is OverlayArc &&
      other.startMin == startMin &&
      other.endMin == endMin &&
      other.track == track &&
      other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(startMin, endMin, track, colorHex);
}

/// Colors for the dial, so the painter stays theme-agnostic.
class DialPalette {
  const DialPalette({
    required this.plate,
    required this.plateStroke,
    required this.wedgeStroke,
    required this.selectedStroke,
    required this.tickMajor,
    required this.tickMinor,
    required this.label,
    required this.numeral,
    required this.hub,
    required this.hubMuted,
    required this.marker,
  });

  final Color plate;
  final Color plateStroke;
  final Color wedgeStroke;
  final Color selectedStroke;
  final Color tickMajor;
  final Color tickMinor;
  final Color label;
  final Color numeral;
  final Color hub;
  final Color hubMuted;
  final Color marker;

  /// The prototype's dark palette.
  static const dark = DialPalette(
    plate: Color(0xFF141A2B),
    plateStroke: Color(0xFF232A42),
    wedgeStroke: Color(0xFF0E1322),
    selectedStroke: Color(0xFFF2E9D8),
    tickMajor: Color(0xFF5A607F),
    tickMinor: Color(0xFF333A54),
    label: Color(0xFFF3F4FB),
    numeral: Color(0xFF737A9C),
    hub: Color(0xFF0B1020),
    hubMuted: Color(0xFF8B90AE),
    marker: Color(0xFFF2E9D8),
  );

  @override
  bool operator ==(Object other) =>
      other is DialPalette &&
      other.plate == plate &&
      other.hub == hub &&
      other.marker == marker;

  @override
  int get hashCode => Object.hash(plate, hub, marker);
}
