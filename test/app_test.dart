import 'package:day_dial/main.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('app boots and shows the dial with mode toggle', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester
        .pump(); // one frame; avoid pumpAndSettle (periodic clock timer)

    expect(find.byType(DialView), findsOneWidget);
    expect(find.text('Compass'), findsOneWidget);
    expect(find.text('Clock'), findsOneWidget);
    expect(find.text('Take meds'), findsOneWidget); // tray from repository

    // Switch to clock mode.
    await tester.tap(find.text('Clock'));
    await tester.pump();

    // Dispose the screen so its periodic timer doesn't leak past the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('checking a tray task persists to the repository', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.completions(), isEmpty);
    await tester.ensureVisible(
      find.text('Take meds'),
    ); // tray is below the fold
    await tester.pump();
    await tester.tap(find.text('Take meds'));
    await tester.pump();
    expect(repo.completions(), hasLength(1)); // written through

    await tester.pumpWidget(const SizedBox());
  });
}
