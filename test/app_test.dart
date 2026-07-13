import 'package:day_dial/main.dart';
import 'package:day_dial/screens/templates_screen.dart';
import 'package:day_dial/widgets/dial_view.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  // A point on the wedge ring: the All-Dial hub covers the center (radius ~82
  // dial-units), so a wedge tap must land past it. At the test window's dial
  // size this offset is comfortably out on the ring.
  const onRing = Offset(160, 0);

  testWidgets('app boots and shows the dial with mode toggle', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester
        .pump(); // one frame; avoid pumpAndSettle (periodic clock timer)

    expect(find.byType(DialView), findsOneWidget);
    expect(find.text('Compass'), findsOneWidget);
    expect(find.text('Clock'), findsOneWidget);
    expect(find.text('Take meds'), findsOneWidget); // tray token from repository

    // Switch to clock mode.
    await tester.tap(find.text('Clock'));
    await tester.pump();

    // Dispose the screen so its periodic timer doesn't leak past the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('checking a tray token persists to the repository', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.completions(), isEmpty);
    await tester.tap(find.text('Take meds')); // the floating token
    await tester.pump();
    expect(repo.completions(), hasLength(1)); // written through

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('add-task pill creates a persisted task', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();
    final before = repo.tasks().length;

    await tester.tap(find.byKey(const Key('add-task')));
    await tester.pump(const Duration(milliseconds: 300)); // dialog opens

    await tester.enterText(find.byType(TextField).first, 'Meditate');
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.tasks().length, before + 1);
    expect(repo.tasks().any((t) => t.label == 'Meditate'), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a wedge opens the popover; delete removes it', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();
    final before = repo.activeProfile().segments.length;

    // Tap the ring (past the hub) to select a wedge; the radial popover opens.
    final dialCenter = tester.getCenter(find.byType(DialView));
    await tester.tapAt(dialCenter + onRing);
    await tester.pump();

    final delete = find.widgetWithText(TextButton, 'Delete');
    await tester.ensureVisible(delete); // popover scrolls if content is tall
    await tester.pump();
    await tester.tap(delete);
    await tester.pump();

    expect(repo.activeProfile().segments.length, before - 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the popover END stepper moves a boundary (day stays 1440)', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    final dialCenter = tester.getCenter(find.byType(DialView));
    await tester.tapAt(dialCenter + onRing);
    await tester.pump();

    List<int> durations() =>
        (repo.activeProfile().segments.map((s) => s.durationMin).toList()
          ..sort());
    final before = durations();

    // Push the selected wedge's end edge out by one 15-minute step. All wedges
    // in the reference day are hours long, so this is always a legal move.
    await tester.tap(find.byTooltip('End later'));
    await tester.pump();

    final after = durations();
    expect(after, isNot(before)); // a boundary moved
    expect(after.fold(0, (a, b) => a + b), 1440); // ring invariant holds

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('incrementing a habit persists an event', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.habitEvents(), isEmpty);
    // Tap the "Water" habit pill to count one.
    await tester.tap(find.text('Water'));
    await tester.pump();
    expect(repo.habitEvents(), hasLength(1)); // written through

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the hub starts then stops tracking, logging one actual', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(repo.logs(), isEmpty);

    // The hub is the center of the dial; a tap there toggles tracking. The hub
    // readout is painted on the canvas (not a widget), so we assert on the
    // durable artifact: an actual is written only when a start is followed by a
    // stop — so one log after two center taps proves both fired.
    await tester.tap(find.byType(DialView)); // center == hub → start
    await tester.pump();
    expect(repo.logs(), isEmpty); // nothing logged mid-session

    await tester.tap(find.byType(DialView)); // center == hub → stop
    await tester.pump();
    expect(repo.logs(), hasLength(1)); // an actual was logged

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long-pressing a token edits it via the actions sheet', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    await tester.longPress(find.text('Take meds'));
    await tester.pump(const Duration(milliseconds: 300)); // sheet opens

    await tester.tap(find.text('Edit…'));
    await tester.pump(const Duration(milliseconds: 300)); // sheet closes, dialog

    await tester.enterText(find.byType(TextField).first, 'Take vitamins');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.tasks().any((t) => t.label == 'Take vitamins'), isTrue);
    expect(repo.tasks().any((t) => t.label == 'Take meds'), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('archiving a token removes it from the tray', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    expect(find.text('Take meds'), findsOneWidget);

    await tester.longPress(find.text('Take meds'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Archive'));
    await tester.pump(const Duration(milliseconds: 300));

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

    // Select a wedge by tapping the ring; the popover offers "Add detail".
    final center = tester.getCenter(find.byType(DialView));
    await tester.tapAt(center + onRing);
    await tester.pump();

    final addDetail = find.text('Add detail');
    await tester.ensureVisible(addDetail); // popover scrolls if content is tall
    await tester.pump();
    await tester.tap(addDetail);
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

  testWidgets('Plans sheet: This day makes an override, Reset removes it', (
    tester,
  ) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    final today = CivilDate.fromDateTime(DateTime.now());
    expect(repo.profileForDate(today).forDate, isNull); // no override yet

    await tester.tap(find.text('Plans'));
    await tester.pump(const Duration(milliseconds: 300)); // sheet opens
    await tester.tap(find.text('Edit this day'));
    await tester.pump(const Duration(milliseconds: 300)); // sheet closes
    expect(repo.profileForDate(today).forDate, isNotNull); // override created

    await tester.tap(find.text('Plans'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reset this day to template'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.profileForDate(today).forDate, isNull); // back to the template

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Plans door opens the templates screen', (tester) async {
    final repo = testRepository();
    await tester.pumpWidget(DayDialApp(repository: repo));
    await tester.pump();

    await tester.tap(find.text('Plans'));
    await tester.pump(const Duration(milliseconds: 300)); // sheet opens
    await tester.tap(find.text('Day templates'));
    await tester.pump(); // sheet pops
    await tester.pump(const Duration(milliseconds: 400)); // route pushes

    expect(find.text('New template'), findsOneWidget); // the screen is up

    await tester.pumpWidget(const SizedBox());
  });
}
