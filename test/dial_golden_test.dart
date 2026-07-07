import 'package:day_dial/painters/dial_painter.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Golden tests for the dial (CLAUDE.md: worth it to catch label-rotation and
/// midnight-wrap regressions). Text renders as the test placeholder font, which
/// is fine — we're guarding geometry and rotation, not typography.
void main() {
  Widget host(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0D18),
      body: Center(child: SizedBox(width: 360, height: 360, child: child)),
    ),
  );

  Future<void> expectGolden(
    WidgetTester tester, {
    required int nowMin,
    required DialMode mode,
    required String file,
  }) async {
    await tester.pumpWidget(
      host(DialView(profile: testProfile(), nowMin: nowMin, mode: mode)),
    );
    await expectLater(
      find.byType(DialView),
      matchesGoldenFile('goldens/$file'),
    );
  }

  testWidgets('compass at 07:30 (morning pinned to top)', (tester) async {
    await expectGolden(
      tester,
      nowMin: 450,
      mode: DialMode.compass,
      file: 'compass_0730.png',
    );
  });

  testWidgets('clock at 07:30 (static disc, hand sweeps)', (tester) async {
    await expectGolden(
      tester,
      nowMin: 450,
      mode: DialMode.clock,
      file: 'clock_0730.png',
    );
  });

  testWidgets('compass at 23:30 (mid-Sleep, wraps midnight)', (tester) async {
    await expectGolden(
      tester,
      nowMin: 1410,
      mode: DialMode.compass,
      file: 'compass_2330.png',
    );
  });

  testWidgets('active block subdivides into its sub-blocks (clock 20:00)', (
    tester,
  ) async {
    // Free time (18:00–23:00) holds Gym 18–19, a gap 19–20, Dinner 20–21,
    // Read 21–23. At 20:00 Free is active, so its wedge subdivides in place.
    final plan = SubBlockPlan({
      'free': [
        const Segment(
          id: 'gym',
          name: 'Gym',
          colorHex: '#2E8B8B',
          startMin: 1080,
          endMin: 1140,
        ),
        const Segment(
          id: 'dinner',
          name: 'Dinner',
          colorHex: '#8E6FB0',
          startMin: 1200,
          endMin: 1260,
        ),
        const Segment(
          id: 'read',
          name: 'Read',
          colorHex: '#5A9FB0',
          startMin: 1260,
          endMin: 1380,
        ),
      ],
    });
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 1200,
          mode: DialMode.clock,
          subBlocks: plan,
        ),
      ),
    );
    await expectLater(
      find.byType(DialView),
      matchesGoldenFile('goldens/subblocks_2000.png'),
    );
  });

  testWidgets('clock at 15:00 with logged actuals on the inner ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 900,
          mode: DialMode.clock,
          actuals: const [
            ActualArc(startMin: 540, endMin: 660, colorHex: '#2E8B8B'),
            ActualArc(startMin: 840, endMin: 900, colorHex: '#3E7CB1'),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(DialView),
      matchesGoldenFile('goldens/actuals_1500.png'),
    );
  });

  testWidgets('clock at 10:00 with a calendar overlay (lane-packed)', (
    tester,
  ) async {
    // Two overlapping meetings (different lanes) plus a standalone one, drawn as
    // thin arcs on the concentric overlay track outside the wedges.
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
                startMin: 570, endMin: 660, track: 1, colorHex: '#5A9FB0'),
            OverlayArc(
                startMin: 780, endMin: 840, track: 0, colorHex: '#7C7CA8'),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(DialView),
      matchesGoldenFile('goldens/overlay_1000.png'),
    );
  });
}
