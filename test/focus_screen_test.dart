import 'package:day_dial/main.dart';
import 'package:day_dial/screens/focus_screen.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('finishing a focus session logs a timer actual', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(MaterialApp(home: FocusScreen(repository: repo)));

    // Start the default 25-min focus, then finish it immediately.
    await tester.tap(find.textContaining('Start'));
    await tester.pump();
    expect(find.text('Finish now (log it)'), findsOneWidget);

    await tester.tap(find.text('Finish now (log it)'));
    await tester.pump();

    expect(repo.logs(), hasLength(1));
    expect(repo.logs().single.source, LogSource.timer);
    expect(find.textContaining('Logged'), findsOneWidget);
  });

  testWidgets('cancel leaves no log and no pending timer', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(MaterialApp(home: FocusScreen(repository: repo)));
    await tester.tap(find.textContaining('Start'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.logs(), isEmpty);
  });

  testWidgets('the focus FAB opens the focus timer', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester.pump();

    await tester.tap(find.byTooltip('Focus timer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('FOCUS ON'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
