import 'package:day_dial/export/exporter.dart';
import 'package:day_dial/main.dart';
import 'package:day_dial/screens/review_screen.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Captures export calls instead of touching the filesystem.
class _FakeExporter implements Exporter {
  String? filename;
  String? contents;

  @override
  Future<String> save(String name, String body) async {
    filename = name;
    contents = body;
    return 'test-location';
  }
}

void main() {
  testWidgets('review shows completion, streaks, and category time', (
    tester,
  ) async {
    final repo = testRepository();
    final today = CivilDate.fromDateTime(DateTime.now());
    // Complete the daily "Take meds" task today -> a current streak of 1.
    final task = repo.tasks().firstWhere((t) => t.label == 'Take meds');
    repo.completeTask(task.id, today);
    // A tracked Deep work actual so the category section has content.
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

    await tester.pumpWidget(MaterialApp(home: ReviewScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget); // app bar
    expect(find.text('STREAKS'), findsOneWidget);
    expect(find.textContaining('🔥'), findsWidgets); // a streak pill
    expect(find.text('Take meds'), findsOneWidget);
    expect(find.text('Deep work'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget); // annual range offered
  });

  testWidgets('the review button opens the review screen', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester.pump();

    await tester.tap(find.byTooltip('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('STREAKS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'exporting logs builds CSV content and hands it to the exporter',
    (tester) async {
      final repo = testRepository();
      final today = CivilDate.fromDateTime(DateTime.now());
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
        ).toIso8601String(),
      );
      final fake = _FakeExporter();

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(repository: repo, exporter: fake),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Logs CSV'), 200);
      await tester.tap(find.text('Logs CSV'));
      await tester.pumpAndSettle();

      expect(fake.filename, endsWith('.csv'));
      expect(fake.contents, contains('date,start,end,durationMin'));
      expect(fake.contents, contains('Deep work'));
      expect(
        find.textContaining('Saved'),
        findsOneWidget,
      ); // confirmation toast
    },
  );
}
