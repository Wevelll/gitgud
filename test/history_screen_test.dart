import 'package:day_dial/screens/history_screen.dart';
import 'package:day_dial/screens/stats_screen.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('history lists tracked sessions for the selected day', (
    tester,
  ) async {
    final repo = testRepository();
    final today = CivilDate.fromDateTime(DateTime.now());
    repo.logActual(
      category: 'Work',
      startTs: DateTime.utc(
        today.year,
        today.month,
        today.day,
        14,
      ).toIso8601String(),
      endTs: DateTime.utc(
        today.year,
        today.month,
        today.day,
        17,
      ).toIso8601String(),
    );

    await tester.pumpWidget(MaterialApp(home: HistoryScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget); // app bar
    expect(find.text('Work'), findsWidgets); // a session row
    expect(find.text('3h'), findsWidgets); // its duration
  });

  testWidgets('history is reachable from the stats screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: StatsScreen(repository: testRepository())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsOneWidget);
  });
}
