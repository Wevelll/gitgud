import 'dart:math' as math;

import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../painters/dial_painter.dart';

/// A self-contained, stateless render of the dial. Kept free of timers and
/// mutable state so it is trivial to golden-test at a fixed time of day.
class DialView extends StatelessWidget {
  const DialView({
    super.key,
    required this.profile,
    required this.nowMin,
    required this.mode,
    this.selectedSegmentId,
    this.onSegmentTapped,
    this.actuals = const [],
    this.subBlocks = const SubBlockPlan.empty(),
    this.palette = DialPalette.dark,
  });

  final DayProfile profile;
  final int nowMin;
  final DialMode mode;
  final String? selectedSegmentId;

  /// Called with the tapped segment's id (null taps — the hub — are ignored).
  final ValueChanged<String>? onSegmentTapped;

  /// Logged actuals to overlay on the inner ring.
  final List<ActualArc> actuals;

  /// Sparse sub-block overlay; the active/selected block subdivides into these.
  final SubBlockPlan subBlocks;
  final DialPalette palette;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapDown: onSegmentTapped == null
                ? null
                : (details) => _handleTap(details.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: DialPainter(
                profile: profile,
                nowMin: nowMin,
                mode: mode,
                palette: palette,
                selectedSegmentId: selectedSegmentId,
                actuals: actuals,
                subBlocks: subBlocks,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Maps a tap to the segment under it, undoing the compass rotation so the
  /// same math works in both modes. The time math itself lives in `core`.
  void _handleTap(Offset local, Size size) {
    final center = size.center(Offset.zero);
    final v = local - center;
    // Angle clockwise from the top (12 o'clock).
    final screenDeg = (math.atan2(v.dx, -v.dy) * 180 / math.pi) % 360;
    // In compass mode the disc is rotated by -timeAngle(now); undo it.
    final thetaDeg = mode == DialMode.compass
        ? -(nowMin / 1440.0 * 360.0)
        : 0.0;
    final discDeg = (screenDeg - thetaDeg) % 360;
    final minute = ((discDeg / 360.0) * 1440).round() % 1440;
    onSegmentTapped!(profile.segmentAt(minute).id);
  }
}
