import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Which concentric region of the dial a point falls in — the basis for
/// distinguishing a hub tap (start/stop tracking) from a wedge tap (select /
/// edit) from a tap in the empty corners (deselect).
enum DialRegion { hub, ring, outside }

/// Pure geometry for the 24-hour dial, shared by the painter (drawing), the
/// [DialView] gesture layer (hit-testing), and the All-Dial shell (anchoring the
/// radial popover and the orbiting tray/habit pills).
///
/// Everything is expressed in the prototype's 360×360 **reference frame** and
/// scaled to the real paint [Size] by [scale], exactly as `DialPainter` does —
/// the radii below mirror the painter's private constants and must stay in sync
/// with them. Keeping this platform-agnostic (only `dart:ui` `Offset`/`Size`, no
/// Flutter, no time math) means it is trivially unit-testable and never pulls
/// business logic into the widget layer (CLAUDE.md golden rule #1).
class DialGeometry {
  /// The reference frame the radii are authored in (matches `DialPainter`).
  static const double referenceExtent = 360.0;

  // Reference radii (360-frame units) — mirror of the painter's constants.
  static const double ro = 150.0; // segment ring outer
  static const double ri = 96.0; // segment ring inner
  static const double rl = 123.0; // wedge label radius
  static const double hub = 82.0; // center hub
  static const double numR = 176.0; // hour numerals
  static const double plate = ro + 12.0; // backing plate

  /// Radius at which orbiting pins (placed tray tokens) sit — just outside the
  /// ring, under the numerals.
  static const double orbit = ro + 6.0;

  static const double _minutesPerDay = 1440.0;

  /// Pixels-per-reference-unit for a given paint size.
  static double scale(Size size) => size.shortestSide / referenceExtent;

  /// The dial center for a given paint size.
  static Offset center(Size size) => size.center(Offset.zero);

  /// Clockwise angle (degrees from the top) of a minute-of-day.
  static double timeAngleDeg(int minute) => minute / _minutesPerDay * 360.0;

  /// The disc's on-screen rotation: in compass mode the whole disc turns by
  /// `-timeAngle(now)` so *now* stays pinned to the fixed top marker; in clock
  /// mode the disc is static. Callers pass `compass` rather than the `DialMode`
  /// enum so this file needs no dependency on the painter.
  static double rotationDeg({required bool compass, required int nowMin}) =>
      compass ? -timeAngleDeg(nowMin) : 0.0;

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// The point at reference-radius [rUnits] and **on-screen** angle
  /// [screenAngleDeg] (i.e. any disc rotation already folded in), scaled to
  /// [size]. Mirrors the painter's `pt`.
  static Offset pointAt(Size size, double rUnits, double screenAngleDeg) {
    final f = scale(size);
    final c = center(size);
    return c +
        Offset(
          rUnits * f * math.sin(_rad(screenAngleDeg)),
          -rUnits * f * math.cos(_rad(screenAngleDeg)),
        );
  }

  /// The on-screen mid-angle of the wedge spanning [startMin]..(+[durationMin]),
  /// including the disc rotation — where the popover for that wedge anchors.
  static double wedgeMidAngleDeg({
    required int startMin,
    required int durationMin,
    required double rotationDeg,
  }) =>
      timeAngleDeg(startMin) + timeAngleDeg(durationMin) / 2.0 + rotationDeg;

  /// Which region [local] (a position in paint-space) falls in. A small
  /// tolerance past the ring outer keeps edge taps selectable; the gap between
  /// the hub and the ring inner counts as ring so no tap is dead.
  static DialRegion regionAt(Size size, Offset local) {
    final f = scale(size);
    final distUnits = (local - center(size)).distance / f;
    if (distUnits <= hub) return DialRegion.hub;
    if (distUnits <= ro + 14.0) return DialRegion.ring;
    return DialRegion.outside;
  }

  /// The minute-of-day under [local], undoing the disc [rotationDeg] so the same
  /// mapping works in both modes. Returns a value in `[0, 1440)`. The caller
  /// resolves which segment that minute belongs to via `core`.
  static int minuteAt(Size size, Offset local, double rotationDeg) {
    final v = local - center(size);
    // Angle clockwise from the top (12 o'clock).
    final screenDeg = (math.atan2(v.dx, -v.dy) * 180 / math.pi) % 360;
    final discDeg = (screenDeg - rotationDeg) % 360;
    final normalized = discDeg < 0 ? discDeg + 360 : discDeg;
    return ((normalized / 360.0) * _minutesPerDay).round() % 1440;
  }
}
