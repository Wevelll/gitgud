import 'dart:math' as math;

import 'package:day_dial/main.dart';
import 'package:day_dial/screens/templates_screen.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:day_dial_core/day_dial_core.dart';
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

  testWidgets('dragging a boundary on the dial resizes and persists', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    // Clock mode pins midnight to the top, so a screen position maps to a
    // known minute regardless of what time the test happens to run at.
    await tester.tap(find.text('Clock'));
    await tester.pump();

    final rect = tester.getRect(find.byType(DialView));
    // A point on the ring at [minute], scaled to however big the dial laid out.
    Offset ringPoint(int minute) {
      final rad = minute / 1440.0 * 2 * math.pi;
      final r = rect.shortestSide / 360.0 * 120; // mid-wedge reference radius
      return rect.center + Offset(r * math.sin(rad), -r * math.cos(rad));
    }

    // Morning ends at 09:00 and Deep work runs 09:00-13:00. Pull the shared
    // boundary out to 10:00: Morning grows by an hour, Deep work gives it up.
    await tester.dragFrom(ringPoint(540), ringPoint(600) - ringPoint(540));
    await tester.pump();

    final segments = repo.activeProfile().segments;
    expect(segments.firstWhere((s) => s.id == 'morning').endMin, 600);
    expect(segments.firstWhere((s) => s.id == 'deep').startMin, 600);
    // Still a gapless ring summing to a day (golden rule #8).
    expect(segments.fold<int>(0, (a, s) => a + s.durationMin), 1440);

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

  testWidgets('editing a tray task updates the repository', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    // Open the actions menu on the seeded 'Take meds' task.
    await tester.ensureVisible(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // menu opens

    await tester.tap(find.text('Edit…'));
    await tester.pump(const Duration(milliseconds: 400)); // dialog opens

    await tester.enterText(find.byType(TextField).first, 'Take vitamins');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.tasks().any((t) => t.label == 'Take vitamins'), isTrue);
    expect(repo.tasks().any((t) => t.label == 'Take meds'), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('archiving a task removes it from the tray', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(find.text('Take meds'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Archive'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Take meds'), findsNothing); // gone from the tray
    expect(repo.tasks().single.archived, isTrue); // but still stored, archived

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('creating an every-N-days task persists an interval rule', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('add-task')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-task')));
    await tester.pump(const Duration(milliseconds: 400)); // dialog opens

    await tester.enterText(find.byType(TextField).first, 'Water plants');

    // Switch the "Repeats" dropdown from 'Every day' to 'Every N days'.
    await tester.tap(find.text('Every day'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Every N days').last);
    await tester.pump(const Duration(milliseconds: 400));

    // Default interval is 2 days; submit as-is.
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 400));

    final added = repo.tasks().firstWhere((t) => t.label == 'Water plants');
    expect(added.recurrence, isA<IntervalRecurrence>());
    expect((added.recurrence as IntervalRecurrence).intervalDays, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('adding a detail sub-block to the selected wedge persists', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();
    expect(repo.subBlocks().isEmpty, isTrue);

    // Select a wedge by tapping the ring (any wedge; angle picks one).
    final center = tester.getCenter(find.byType(DialView));
    await tester.tapAt(center + const Offset(90, 0));
    await tester.pump();

    // The selected-block editor now offers "Add detail". The dialog defaults
    // its times to inside the parent, so accepting them yields a valid sub-block.
    await tester.ensureVisible(find.text('Add detail'));
    await tester.pump();
    await tester.tap(find.text('Add detail'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).first, 'Focus');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.subBlocks().isEmpty, isFalse); // a sub-block was persisted

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('day templates: create a template by durations', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(
      MaterialApp(home: TemplatesScreen(repository: repo)),
    );
    await tester.pump();
    final before = repo.profiles().length;

    await tester.tap(find.text('New template'));
    await tester.pump(const Duration(milliseconds: 400)); // dialog opens

    // Defaults are Sleep/Work/Free 8/8/8 (totals 24h); just create it.
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.profiles().length, before + 1);
    final added = repo.profiles().firstWhere((p) => p.name == 'Weekend');
    expect(added.segments.length, 3);
    expect(added.segments.map((s) => s.durationMin), [480, 480, 480]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing scope: This day makes an override, Reset removes it', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    final today = CivilDate.fromDateTime(DateTime.now());
    expect(repo.profileForDate(today).forDate, isNull); // no override yet

    await tester.ensureVisible(find.text('This day'));
    await tester.pump();
    await tester.tap(find.text('This day'));
    await tester.pump();
    expect(repo.profileForDate(today).forDate, isNotNull); // override created

    await tester.ensureVisible(find.text('Reset'));
    await tester.pump();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(repo.profileForDate(today).forDate, isNull); // back to the template

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the templates button opens the templates screen', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    await tester.tap(find.byTooltip('Day templates'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('Day templates'), findsOneWidget); // the screen's app bar
    expect(find.text('New template'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('midnight rollover', () {
    // A planner gets left open overnight. Everything keyed to "today" has to
    // move on when the clock passes midnight — otherwise the app keeps
    // operating on yesterday.
    const beforeMidnight = Duration(hours: 23, minutes: 59, seconds: 30);
    const afterMidnight = Duration(minutes: 0, seconds: 30);
    final thursday = DateTime(2026, 8, 20);
    final friday = DateTime(2026, 8, 21);

    testWidgets('ticking a task after midnight completes it for the new date', (
      tester,
    ) async {
      final repo = testRepository();
      var now = thursday.add(beforeMidnight);
      await tester.pumpWidget(DayDialApp(repository: repo, clock: () => now));
      await tester.pump();

      now = friday.add(afterMidnight);
      await tester.pump(const Duration(seconds: 11)); // one clock tick

      await tester.ensureVisible(find.text('Take meds'));
      await tester.pump();
      await tester.tap(find.text('Take meds'));
      await tester.pump();

      expect(repo.completions(), hasLength(1));
      expect(repo.completions().single.date, const CivilDate(2026, 8, 21));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the ring follows the new date to its weekday template', (
      tester,
    ) async {
      final repo = testRepository();
      // A Friday-only template. Thursday resolves to the default, Friday to
      // this one, so crossing midnight has to swap the ring.
      repo.addProfile(
        DayProfile.fromDurations(
          id: 'friday',
          name: 'Friday',
          activeDaysMask: 1 << 4, // Monday = bit 0, so Friday = bit 4
          segmentIds: const ['rest', 'play'],
          blocks: const [
            (name: 'Rest', colorHex: '#4B4FA6', minutes: 600),
            (name: 'Play', colorHex: '#6FA85B', minutes: 840),
          ],
        ),
      );

      var now = thursday.add(beforeMidnight);
      await tester.pumpWidget(DayDialApp(repository: repo, clock: () => now));
      await tester.pump();
      expect(repo.activeProfile().id, isNot('friday'));

      now = friday.add(afterMidnight);
      await tester.pump(const Duration(seconds: 11));

      expect(repo.activeProfile().id, 'friday');
      expect(find.text('FRIDAY'), findsOneWidget); // the header follows too

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an ordinary tick within the same day changes nothing', (
      tester,
    ) async {
      final repo = testRepository();
      var now = thursday.add(const Duration(hours: 9));
      await tester.pumpWidget(DayDialApp(repository: repo, clock: () => now));
      await tester.pump();
      final before = repo.activeProfile().id;

      now = thursday.add(const Duration(hours: 9, minutes: 1));
      await tester.pump(const Duration(seconds: 11));

      expect(repo.activeProfile().id, before);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
