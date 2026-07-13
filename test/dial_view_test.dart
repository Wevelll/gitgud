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

  testWidgets('tapping the hub fires the hub callback, not a selection', (
    tester,
  ) async {
    String? tapped;
    var hub = 0;
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 450,
          mode: DialMode.clock,
          onSegmentTapped: (id) => tapped = id,
          onHubTapped: () => hub++,
        ),
      ),
    );
    // Dead center is the hub (start/stop tracking), never a wedge selection.
    await tester.tapAt(tester.getCenter(find.byType(DialView)));
    expect(hub, 1);
    expect(tapped, isNull);
  });

  testWidgets('tapping outside the ring fires the background callback', (
    tester,
  ) async {
    String? tapped;
    var background = 0;
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 450,
          mode: DialMode.clock,
          onSegmentTapped: (id) => tapped = id,
          onBackgroundTapped: () => background++,
        ),
      ),
    );
    // A point past the ring outer (radius ~175 in the 360 frame) is outside.
    final center = tester.getCenter(find.byType(DialView));
    await tester.tapAt(center + const Offset(0, -175));
    expect(background, 1);
    expect(tapped, isNull);
  });

  testWidgets('long-pressing the hub fires the long-press callback', (
    tester,
  ) async {
    var longPress = 0;
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 450,
          mode: DialMode.clock,
          onHubLongPressed: () => longPress++,
        ),
      ),
    );
    await tester.longPressAt(tester.getCenter(find.byType(DialView)));
    expect(longPress, 1);
  });

  testWidgets('renders a calendar overlay without error', (tester) async {
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 600,
          mode: DialMode.clock,
          overlay: const [
            OverlayArc(
                startMin: 540, endMin: 600, track: 0, colorHex: '#7C7CA8'),
            OverlayArc(
                startMin: 570, endMin: 630, track: 1, colorHex: '#C98A3E'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(DialView), findsOneWidget);
  });

  test('painter repaints when the overlay changes', () {
    final prof = testProfile(); // one instance: isolate the overlay comparison
    DialPainter painter(List<OverlayArc> overlay) => DialPainter(
          profile: prof,
          nowMin: 600,
          mode: DialMode.clock,
          palette: DialPalette.dark,
          overlay: overlay,
        );
    final base = painter(const [
      OverlayArc(startMin: 540, endMin: 600, track: 0, colorHex: '#7C7CA8'),
    ]);
    expect(base.shouldRepaint(painter(const [])), isTrue);
    expect(
      base.shouldRepaint(painter(const [
        OverlayArc(startMin: 540, endMin: 600, track: 0, colorHex: '#7C7CA8'),
      ])),
      isFalse,
    );
  });

  test('painter repaints when tracking starts or stops', () {
    final prof = testProfile();
    DialPainter painter(DialTracking? tracking) => DialPainter(
          profile: prof,
          nowMin: 600,
          mode: DialMode.clock,
          palette: DialPalette.dark,
          tracking: tracking,
        );
    final idle = painter(null);
    expect(
      idle.shouldRepaint(painter(const DialTracking(
        category: 'Deep work',
        colorHex: '#2E8B8B',
        elapsedLabel: '00:05',
      ))),
      isTrue,
    );
    expect(idle.shouldRepaint(painter(null)), isFalse);
  });
}
