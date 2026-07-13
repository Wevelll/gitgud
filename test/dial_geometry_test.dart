import 'dart:ui';

import 'package:day_dial/painters/dial_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 360×360 box makes the reference frame 1:1 (scale == 1, center == 180,180),
  // so distances and angles read directly in reference units/degrees.
  const size = Size(360, 360);
  final center = DialGeometry.center(size);

  group('regionAt', () {
    test('dead center is the hub', () {
      expect(DialGeometry.regionAt(size, center), DialRegion.hub);
    });

    test('a point on the wedge ring is the ring', () {
      expect(
        DialGeometry.regionAt(size, center + const Offset(120, 0)),
        DialRegion.ring,
      );
    });

    test('the gap between hub and ring inner still counts as ring', () {
      // 90 units: past the hub (82) but short of the ring inner (96).
      expect(
        DialGeometry.regionAt(size, center + const Offset(0, -90)),
        DialRegion.ring,
      );
    });

    test('far outside the plate is outside', () {
      expect(
        DialGeometry.regionAt(size, center + const Offset(178, 0)),
        DialRegion.outside,
      );
    });
  });

  group('minuteAt (clock mode, no rotation)', () {
    test('straight up is midnight', () {
      expect(
        DialGeometry.minuteAt(size, center + const Offset(0, -120), 0),
        0,
      );
    });

    test('right is 06:00, down is 12:00, left is 18:00', () {
      expect(
        DialGeometry.minuteAt(size, center + const Offset(120, 0), 0),
        360,
      );
      expect(
        DialGeometry.minuteAt(size, center + const Offset(0, 120), 0),
        720,
      );
      expect(
        DialGeometry.minuteAt(size, center + const Offset(-120, 0), 0),
        1080,
      );
    });
  });

  group('minuteAt (compass mode)', () {
    test('the top marker reads the current minute', () {
      const now = 360; // 06:00
      final rot = DialGeometry.rotationDeg(compass: true, nowMin: now);
      expect(
        DialGeometry.minuteAt(size, center + const Offset(0, -120), rot),
        now,
      );
    });
  });

  test('wedgeMidAngleDeg is the arc center including rotation', () {
    // A wedge from 00:00 spanning 120 min: its mid is at 15° with no rotation.
    expect(
      DialGeometry.wedgeMidAngleDeg(
        startMin: 0,
        durationMin: 120,
        rotationDeg: 0,
      ),
      15.0,
    );
  });

  test('pointAt places the top of the ring above center', () {
    final p = DialGeometry.pointAt(size, DialGeometry.ro, 0);
    expect(p.dx, closeTo(center.dx, 0.001));
    expect(p.dy, closeTo(center.dy - DialGeometry.ro, 0.001));
  });
}
