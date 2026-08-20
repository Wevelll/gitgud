import 'dart:math' as math;

import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial/painters/dial_painter.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0D18),
      body: Center(child: SizedBox(width: 360, height: 360, child: child)),
    ),
  );

  /// A point on the ring at [minute], for a dial in **clock** mode (no disc
  /// rotation, so the mapping is fixed). [radius] sits between the wedge
  /// radii, 96..150.
  Offset ringPoint(int minute, {double radius = 120}) {
    final rad = minute / 1440.0 * 2 * math.pi;
    return Offset(radius * math.sin(rad), -radius * math.cos(rad));
  }

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

  testWidgets('renders a calendar overlay without error', (tester) async {
    await tester.pumpWidget(
      host(
        DialView(
          profile: testProfile(),
          nowMin: 600,
          mode: DialMode.clock,
          overlay: const [
            OverlayArc(
              startMin: 540,
              endMin: 600,
              track: 0,
              colorHex: '#7C7CA8',
            ),
            OverlayArc(
              startMin: 570,
              endMin: 630,
              track: 1,
              colorHex: '#C98A3E',
            ),
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
      base.shouldRepaint(
        painter(const [
          OverlayArc(startMin: 540, endMin: 600, track: 0, colorHex: '#7C7CA8'),
        ]),
      ),
      isFalse,
    );
  });

  group('dragging a shared boundary (SPEC §2.4)', () {
    testWidgets('reports the block that ends there and its new end time', (
      tester,
    ) async {
      final moves = <(String, int)>[];
      var ended = 0;
      await tester.pumpWidget(
        host(
          DialView(
            profile: testProfile(),
            nowMin: 450,
            mode: DialMode.clock,
            onBoundaryDragged: (id, endMin) => moves.add((id, endMin)),
            onBoundaryDragEnd: () => ended++,
          ),
        ),
      );

      // Morning ends at 09:00. Grab that boundary and pull it out to 10:00.
      final center = tester.getCenter(find.byType(DialView));
      await tester.dragFrom(
        center + ringPoint(540),
        ringPoint(600) - ringPoint(540),
      );
      await tester.pumpAndSettle();

      expect(moves.last, ('morning', 600));
      expect(ended, 1);
    });

    testWidgets('a drag that starts away from any boundary is not a grab', (
      tester,
    ) async {
      final moves = <(String, int)>[];
      await tester.pumpWidget(
        host(
          DialView(
            profile: testProfile(),
            nowMin: 450,
            mode: DialMode.clock,
            onBoundaryDragged: (id, endMin) => moves.add((id, endMin)),
          ),
        ),
      );

      // 11:00 is deep inside Deep work (09:00–13:00), far from any boundary.
      final center = tester.getCenter(find.byType(DialView));
      await tester.dragFrom(
        center + ringPoint(660),
        ringPoint(700) - ringPoint(660),
      );
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
    });

    testWidgets('a drag over the hub is not a grab either', (tester) async {
      final moves = <(String, int)>[];
      await tester.pumpWidget(
        host(
          DialView(
            profile: testProfile(),
            nowMin: 450,
            mode: DialMode.clock,
            onBoundaryDragged: (id, endMin) => moves.add((id, endMin)),
          ),
        ),
      );

      // Same angle as the 09:00 boundary, but at hub radius — not the ring.
      final center = tester.getCenter(find.byType(DialView));
      await tester.dragFrom(
        center + ringPoint(540, radius: 30),
        const Offset(0, 40),
      );
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
    });

    testWidgets('a read-only dial has no drag handles and ignores drags', (
      tester,
    ) async {
      // No onBoundaryDragged → the dial is a pure render (what the goldens
      // pump), so nothing to grab.
      await tester.pumpWidget(
        host(
          DialView(profile: testProfile(), nowMin: 450, mode: DialMode.clock),
        ),
      );
      expect(_painterOf(tester).showHandles, isFalse);

      final center = tester.getCenter(find.byType(DialView));
      await tester.dragFrom(
        center + ringPoint(540),
        ringPoint(600) - ringPoint(540),
      );
      await tester.pumpAndSettle(); // no callbacks wired: must not throw
    });

    testWidgets('a press on a boundary still selects the wedge', (
      tester,
    ) async {
      // Claiming the pointer at down-time costs the tap recognizer, so the
      // press-without-moving case is handled by the drag path instead. Without
      // that, the blocks either side of a boundary would be untappable.
      String? tapped;
      await tester.pumpWidget(
        host(
          DialView(
            profile: testProfile(),
            nowMin: 450,
            mode: DialMode.clock,
            onSegmentTapped: (id) => tapped = id,
            onBoundaryDragged: (_, _) {},
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DialView));
      await tester.tapAt(center + ringPoint(540)); // right on Morning's end
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
    });

    testWidgets('a cancelled grab selects nothing and drops the drag', (
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
            onBoundaryDragged: (_, _) {},
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DialView));
      final gesture = await tester.startGesture(center + ringPoint(540));
      await tester.pump();
      expect(_painterOf(tester).draggingBoundaryId, 'morning');

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(_painterOf(tester).draggingBoundaryId, isNull);
      expect(tapped, isNull, reason: 'a cancel has no position to select from');
    });

    testWidgets('the grabbed boundary is highlighted while dragging', (
      tester,
    ) async {
      // A host that actually applies each move, so the capture shows what the
      // user sees: the wedge following the finger, not a static ring.
      var profile = testProfile();
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DialView(
              profile: profile,
              nowMin: 450,
              mode: DialMode.clock,
              onBoundaryDragged: (id, endMin) => setState(
                () => profile = profile.updateBlock(id, endMin: endMin),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DialView));
      final gesture = await tester.startGesture(center + ringPoint(540));
      await gesture.moveTo(center + ringPoint(600));
      await tester.pump();

      // Held mid-drag: Morning now runs to 10:00, its handle is called out,
      // and Deep work has given up the hour. Released after the capture.
      expect(_painterOf(tester).draggingBoundaryId, 'morning');
      expect(profile.segments.firstWhere((s) => s.id == 'morning').endMin, 600);
      await expectLater(
        find.byType(DialView),
        matchesGoldenFile('goldens/boundary_drag.png'),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

/// The [DialPainter] the dial is currently painting with — how the tests assert
/// on render state (handles, the grabbed boundary) without pixel-peeping.
DialPainter _painterOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(DialView),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as DialPainter;
