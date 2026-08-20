import 'dart:io';

import 'package:day_dial/main.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The day view adapts to the window it's in: one scrolling column on a phone
/// or a narrow window, two columns on a desktop one — the dial on the left
/// staying put while the panels on the right scroll (SPEC §8, desktop-first).
void main() {
  /// Loads the app's bundled Roboto so golden captures show real text instead
  /// of the test framework's placeholder boxes — the point of this golden is
  /// to be *readable* when reviewing the layout.
  Future<void> loadRoboto() async {
    final bytes = File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  /// Pumps the app in a window of [size] and settles one frame.
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DayDialApp(
        repository: testRepository(),
        clock: () => DateTime(2026, 8, 20, 9, 30),
      ),
    );
    await tester.pump();
  }

  testWidgets('a desktop window puts the dial and the tray side by side', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));

    final dial = tester.getRect(find.byType(DialView));
    final tray = tester.getRect(find.text('MUST-DO TODAY · NO FIXED TIME'));

    // Side by side, not stacked: the tray starts to the right of the dial.
    expect(tray.left, greaterThan(dial.right));
    // And both are on screen at once — no scrolling to reach the tray.
    expect(tray.top, lessThan(800));
    expect(dial.bottom, lessThan(800));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a narrow window keeps the single stacked column', (
    tester,
  ) async {
    await pumpAt(tester, const Size(500, 900));

    final dial = tester.getRect(find.byType(DialView));
    final tray = tester.getRect(find.text('MUST-DO TODAY · NO FIXED TIME'));

    // Stacked: the tray is below the dial, in the same column.
    expect(tray.top, greaterThan(dial.bottom));
    expect(tray.left, lessThan(dial.right));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dial gets meaningfully bigger on a desktop window', (
    tester,
  ) async {
    await pumpAt(tester, const Size(500, 900));
    final narrow = tester.getRect(find.byType(DialView)).width;
    await tester.pumpWidget(const SizedBox());

    await pumpAt(tester, const Size(1280, 800));
    final wide = tester.getRect(find.byType(DialView)).width;

    expect(wide, greaterThan(narrow));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop layout golden', (tester) async {
    await loadRoboto();
    await pumpAt(tester, const Size(1280, 800));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_1280.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
