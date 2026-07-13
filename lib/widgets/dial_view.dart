import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../painters/dial_geometry.dart';
import '../painters/dial_painter.dart';

/// A self-contained, stateless render of the dial. Kept free of timers and
/// mutable state so it is trivial to golden-test at a fixed time of day.
///
/// The gesture layer classifies each tap by concentric region (via
/// [DialGeometry]) so the All-Dial shell can put verbs on the things themselves:
/// the hub is the tracking control, a wedge is selected/edited, and a tap in the
/// empty corners deselects. All time math still lives in `core`.
class DialView extends StatelessWidget {
  const DialView({
    super.key,
    required this.profile,
    required this.nowMin,
    required this.mode,
    this.selectedSegmentId,
    this.onSegmentTapped,
    this.onHubTapped,
    this.onHubLongPressed,
    this.onBackgroundTapped,
    this.actuals = const [],
    this.overlay = const [],
    this.subBlocks = const SubBlockPlan.empty(),
    this.tracking,
    this.palette = DialPalette.dark,
  });

  final DayProfile profile;
  final int nowMin;
  final DialMode mode;
  final String? selectedSegmentId;

  /// Called with the tapped segment's id when a wedge is tapped.
  final ValueChanged<String>? onSegmentTapped;

  /// Called when the center hub is tapped — the start/stop tracking control.
  final VoidCallback? onHubTapped;

  /// Called on a long-press of the hub — begins a focus/Pomodoro session.
  final VoidCallback? onHubLongPressed;

  /// Called when a tap lands outside the ring (the empty corners) — deselects.
  final VoidCallback? onBackgroundTapped;

  /// Logged actuals to overlay on the inner ring.
  final List<ActualArc> actuals;

  /// Read-only calendar events, drawn on a concentric track outside the ring.
  final List<OverlayArc> overlay;

  /// Sparse sub-block overlay; the active/selected block subdivides into these.
  final SubBlockPlan subBlocks;

  /// In-progress tracking session; when set the hub shows the recording state.
  final DialTracking? tracking;
  final DialPalette palette;

  bool get _interactive =>
      onSegmentTapped != null ||
      onHubTapped != null ||
      onHubLongPressed != null ||
      onBackgroundTapped != null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapUp:
                _interactive ? (d) => _handleTap(d.localPosition, size) : null,
            onLongPressStart: onHubLongPressed == null
                ? null
                : (d) => _handleLongPress(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: DialPainter(
                profile: profile,
                nowMin: nowMin,
                mode: mode,
                palette: palette,
                selectedSegmentId: selectedSegmentId,
                actuals: actuals,
                overlay: overlay,
                subBlocks: subBlocks,
                tracking: tracking,
              ),
            ),
          );
        },
      ),
    );
  }

  double _rotation() => DialGeometry.rotationDeg(
        compass: mode == DialMode.compass,
        nowMin: nowMin,
      );

  void _handleTap(Offset local, Size size) {
    switch (DialGeometry.regionAt(size, local)) {
      case DialRegion.hub:
        onHubTapped?.call();
      case DialRegion.ring:
        final minute = DialGeometry.minuteAt(size, local, _rotation());
        onSegmentTapped?.call(profile.segmentAt(minute).id);
      case DialRegion.outside:
        onBackgroundTapped?.call();
    }
  }

  void _handleLongPress(Offset local, Size size) {
    if (DialGeometry.regionAt(size, local) == DialRegion.hub) {
      onHubLongPressed?.call();
    }
  }
}
