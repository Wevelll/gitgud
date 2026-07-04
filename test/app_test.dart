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

  testWidgets('add-task dialog creates a persisted task', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();
    final before = repo.tasks().length;

    await tester.ensureVisible(find.byKey(const Key('add-task')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-task')));
    await tester.pump(const Duration(milliseconds: 300)); // dialog opens

    await tester.enterText(find.byType(TextField).first, 'Meditate');
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.tasks().length, before + 1);
    expect(repo.tasks().any((t) => t.label == 'Meditate'), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selecting a wedge then deleting removes it', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();
    final before = repo.activeProfile().segments.length;

    // Tap the dial to select a wedge (compass mode; any on-ring point works).
    final dialCenter = tester.getCenter(find.byType(DialView));
    await tester.tapAt(dialCenter + const Offset(90, 0));
    await tester.pump();

    await tester.ensureVisible(find.byTooltip('Delete'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();

    expect(repo.activeProfile().segments.length, before - 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('incrementing a habit persists an event', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.habitEvents(), isEmpty);
    // Tap the + on the first habit row (there's one: "Water").
    final plus = find.byIcon(Icons.add_circle).first;
    await tester.ensureVisible(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pump();
    expect(repo.habitEvents(), hasLength(1)); // written through

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('start then stop tracking writes one actual', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.logs(), isEmpty);
    await tester.ensureVisible(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget); // now tracking
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(repo.logs(), hasLength(1)); // an actual was logged

    await tester.pumpWidget(const SizedBox());
  });
}
