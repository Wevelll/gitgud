import 'package:day_dial/painters/dial_painter.dart';
import 'package:day_dial/widgets/dial_view.dart';
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
}
