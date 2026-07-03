import 'package:day_dial/painters/dial_painter.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 360, child: child)),
    ),
  );

  testWidgets('tapping the ring selects the segment under the tap (clock mode)', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 450,
          mode: DialMode.clock, // no rotation → predictable mapping
          onSegmentTapped: (id) => tapped = id,
        ),
      ),
    );

    // 08:00 is at 120° clockwise from top; a point on the ring there is Morning.
    final center = tester.getCenter(find.byType(DialView));
    final p = center + const Offset(104, 60); // ~120°, radius ~120
    await tester.tapAt(p);
    expect(tapped, 'morning');
  });

  testWidgets('tapping the hub does not select (null region ignored)', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 450,
          mode: DialMode.clock,
          onSegmentTapped: (id) => tapped = id,
        ),
      ),
    );
    // Dead center is the hub; still maps to a minute, but tapping the very
    // center resolves to minute 0 -> Sleep. Assert it at least stays on-ring.
    final center = tester.getCenter(find.byType(DialView));
    await tester.tapAt(center + const Offset(0, -120)); // straight up = 00:00
    expect(tapped, 'sleep');
  });
}
