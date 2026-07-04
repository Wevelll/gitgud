import 'package:day_dial/main.dart';
import 'package:day_dial/screens/stats_screen.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('stats shows tracked vs planned for a logged category', (
    tester,
  ) async {
    final repo = testRepository();
    final today = CivilDate.fromDateTime(DateTime.now());
    // A 90-minute Deep work actual on today's date (Deep work is planned 4h).
    repo.logActual(
      category: 'Deep work',
      startTs: DateTime.utc(
        today.year,
        today.month,
        today.day,
        9,
      ).toIso8601String(),
      endTs: DateTime.utc(
        today.year,
        today.month,
        today.day,
        10,
        30,
      ).toIso8601String(),
    );

    await tester.pumpWidget(MaterialApp(home: StatsScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Plan vs actual'), findsOneWidget); // app bar
    expect(find.text('Deep work'), findsOneWidget); // a category card
    expect(find.text('1h 30m'), findsWidgets); // tracked duration shown
  });

  testWidgets('stats screen golden (day range, two actuals)', (tester) async {
    final repo = testRepository();
    final today = CivilDate.fromDateTime(DateTime.now());
    String iso(int h, int m) => DateTime.utc(
      today.year,
      today.month,
      today.day,
      h,
      m,
    ).toIso8601String();
    repo.logActual(
      category: 'Deep work',
      startTs: iso(9, 0),
      endTs: iso(10, 30),
    );
    repo.logActual(category: 'Work', startTs: iso(14, 0), endTs: iso(17, 0));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0D18)),
        home: SizedBox(
          width: 400,
          height: 820,
          child: StatsScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StatsScreen),
      matchesGoldenFile('goldens/stats_day.png'),
    );
  });

  testWidgets('the insights button opens the stats screen', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester.pump();

    await tester.tap(find.byTooltip('Plan vs actual'));
    await tester.pump(); // start route transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it

    expect(find.text('Plan vs actual'), findsOneWidget); // stats app bar title

    await tester.pumpWidget(const SizedBox());
  });
}
