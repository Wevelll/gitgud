import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:test/test.dart';

DayProfile weekday() => DayProfile.ring(
  id: 'weekday',
  name: 'Weekday',
  isDefault: true,
  segmentIds: const ['sleep', 'morning', 'deep', 'lunch', 'work', 'free'],
  spans: const [
    (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
    (startMin: 420, name: 'Morning', colorHex: '#C98A3E'),
    (startMin: 540, name: 'Deep work', colorHex: '#2E8B8B'),
    (startMin: 780, name: 'Lunch', colorHex: '#B5624F'),
    (startMin: 840, name: 'Work', colorHex: '#3E7CB1'),
    (startMin: 1080, name: 'Free time', colorHex: '#6FA85B'),
  ],
);

DayProfile weekend() => DayProfile.ring(
  id: 'weekend',
  name: 'Weekend',
  spans: const [
    (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
    (startMin: 540, name: 'Chill', colorHex: '#6FA85B'),
  ],
);

// Friday 2026-07-03, 07:30 — inside Morning.
DateTime fixedClock() => DateTime(2026, 7, 3, 7, 30);

InMemoryDayRepository repo() =>
    InMemoryDayRepository(profiles: [weekday(), weekend()], clock: fixedClock);

void main() {
  group('consent gating', () {
    test('read tools never touch the consent gate', () async {
      final gate = CallbackConsent((_) async => true);
      final tools = DayDialTools(repo(), gate, clock: fixedClock);

      await tools.call('get_current_block');
      await tools.call('get_day');
      await tools.call('list_upcoming');
      await tools.call('get_recurring_tasks');
      await tools.call('get_stats');

      expect(gate.seen, isEmpty);
    });

    test('every mutating tool asks for consent', () async {
      final gate = CallbackConsent((_) async => true);
      final tools = DayDialTools(repo(), gate, clock: fixedClock);

      await tools.call('add_block', {
        'name': 'Gym',
        'start': '10:00',
        'end': '11:00',
      });
      expect(gate.seen.single.tool, 'add_block');
    });

    test('denied consent throws and leaves state unchanged', () async {
      final r = repo();
      final tools = DayDialTools(r, const DenyAllConsent(), clock: fixedClock);
      final before = r.activeProfile().segments.length;

      expect(
        () => tools.call('add_block', {
          'name': 'Gym',
          'start': '10:00',
          'end': '11:00',
        }),
        throwsA(isA<ConsentDeniedException>()),
      );
      expect(r.activeProfile().segments.length, before);
    });

    test('delete_block is flagged destructive to the gate', () async {
      final gate = CallbackConsent((_) async => true);
      final tools = DayDialTools(repo(), gate, clock: fixedClock);

      await tools.call('delete_block', {'id': 'lunch'});
      expect(gate.seen.single.destructive, isTrue);
    });

    test('spec marks exactly the writes as mutating', () {
      final mutating = DayDialTools.specs
          .where((s) => s.mutates)
          .map((s) => s.name)
          .toSet();
      expect(mutating, {
        'add_block',
        'update_block',
        'delete_block',
        'add_recurring_task',
        'complete_task',
        'update_recurring_task',
        'set_task_archived',
        'delete_recurring_task',
        'add_sub_block',
        'update_sub_block',
        'delete_sub_block',
        'switch_profile',
        'log_actual',
        'add_habit',
        'log_habit',
      });
      expect(
        DayDialTools.specs
            .where((s) => s.destructive)
            .map((s) => s.name)
            .toSet(),
        {'delete_block', 'delete_recurring_task', 'delete_sub_block'},
      );
    });
  });

  group('read tools', () {
    final tools = DayDialTools(
      repo(),
      const AllowAllConsent(),
      clock: fixedClock,
    );

    test('get_current_block reflects the clock', () async {
      final r = await tools.call('get_current_block') as Map;
      expect(r['name'], 'Morning');
      expect(r['minutesRemaining'], 90); // 07:30 -> 09:00
      expect(r['profile'], 'Weekday');
    });

    test('get_current_block accepts an explicit now', () async {
      final r = await tools.call('get_current_block', {'now': '13:30'}) as Map;
      expect(r['name'], 'Lunch');
    });

    test('list_upcoming returns accumulating minutes', () async {
      final r = await tools.call('list_upcoming', {'count': 2}) as List;
      expect(r.map((e) => e['name']).toList(), ['Deep work', 'Lunch']);
      expect(r.first['inMinutes'], 90);
    });

    test('get_day lists all blocks and the tray', () async {
      final r = await tools.call('get_day') as Map;
      expect((r['blocks'] as List).length, 6);
      expect(r['date'], '2026-07-03');
    });
  });

  group('write flows', () {
    test('add / update / delete block round-trip', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);

      final added =
          await tools.call('add_block', {
                'name': 'Gym',
                'start': '10:00',
                'end': '11:00',
              })
              as Map;
      final id = added['id'] as String;
      expect(r.activeProfile().segments.any((s) => s.id == id), isTrue);

      final updated =
          await tools.call('update_block', {'id': id, 'name': 'Workout'})
              as Map;
      expect(updated['name'], 'Workout');

      await tools.call('delete_block', {'id': id});
      expect(r.activeProfile().segments.any((s) => s.id == id), isFalse);
    });

    test('recurring task: add, complete, and query tray', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);

      final task =
          await tools.call('add_recurring_task', {
                'label': 'Take meds',
                'recurrence': 'daily',
              })
              as Map;
      final id = task['id'] as String;

      var pending =
          await tools.call('get_recurring_tasks', {'status': 'pending'})
              as List;
      expect(pending.single['label'], 'Take meds');

      await tools.call('complete_task', {'id': id});

      pending =
          await tools.call('get_recurring_tasks', {'status': 'pending'})
              as List;
      expect(pending, isEmpty);
      final done =
          await tools.call('get_recurring_tasks', {'status': 'done'}) as List;
      expect(done.single['id'], id);
    });

    test('switch_profile changes the active layout', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);
      await tools.call('switch_profile', {'profile': 'weekend'});
      expect(r.activeProfile().name, 'Weekend');
    });

    test('log_actual feeds get_stats variance', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);

      await tools.call('log_actual', {
        'category': 'Deep work',
        'start': '2026-07-03T09:00:00Z',
        'end': '2026-07-03T11:00:00Z',
      });

      final stats = await tools.call('get_stats', {'range': 'day'}) as Map;
      final rows = (stats['perCategory'] as List).cast<Map<String, Object?>>();
      final deep = rows.firstWhere((e) => e['category'] == 'Deep work');
      expect(deep['plannedMin'], 240); // Deep work is 4h in the profile
      expect(deep['actualMin'], 120); // logged 2h
      expect(deep['deltaMin'], -120);
    });

    test('habit: add, increment, and read the tally', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);

      final habit =
          await tools.call('add_habit', {
                'label': 'Water',
                'polarity': 'good',
                'target': 8,
              })
              as Map;
      final id = habit['id'] as String;

      await tools.call('log_habit', {'id': id});
      final logged = await tools.call('log_habit', {'id': id}) as Map;
      expect(logged['count'], 2);

      final habits = await tools.call('get_habits') as List;
      final water = habits.cast<Map<String, Object?>>().firstWhere(
        (h) => h['id'] == id,
      );
      expect(water['count'], 2);
      expect(water['target'], 8);

      // Decrement via negative delta.
      final down =
          await tools.call('log_habit', {'id': id, 'delta': -1}) as Map;
      expect(down['count'], 1);
    });

    test('log_actual by blockId derives the category', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);
      final log =
          await tools.call('log_actual', {
                'blockId': 'work',
                'start': '2026-07-03T14:00:00Z',
                'end': '2026-07-03T15:30:00Z',
              })
              as Map;
      expect(log['category'], 'Work');
      expect(log['minutes'], 90);
    });

    test('recurring task: update, archive, and delete', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);
      final task =
          await tools.call('add_recurring_task', {
                'label': 'Meds',
                'recurrence': 'daily',
              })
              as Map;
      final id = task['id'] as String;

      final updated =
          await tools.call('update_recurring_task', {
                'id': id,
                'label': 'Vitamins',
                'recurrence': 'weekly:1,3,5',
              })
              as Map;
      expect(updated['label'], 'Vitamins');
      expect(updated['recurrence'], 'weekly:1,3,5');

      // Archive hides it from the tray (Friday 2026-07-03 is weekday 5).
      await tools.call('set_task_archived', {'id': id, 'archived': true});
      final tray = await tools.call('get_recurring_tasks') as List;
      expect(tray.any((t) => t['id'] == id), isFalse);

      await tools.call('set_task_archived', {'id': id, 'archived': false});
      await tools.call('delete_recurring_task', {'id': id});
      expect(r.tasks(), isEmpty);
    });

    test('sub-blocks: add, read, update, and delete over MCP', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);

      // Free time is 18:00–23:00 in the weekday ring.
      final added =
          await tools.call('add_sub_block', {
                'parentId': 'free',
                'name': 'Gym',
                'start': '18:00',
                'end': '19:00',
              })
              as Map;
      final id = added['id'] as String;
      expect(added['parentId'], 'free');

      final list =
          await tools.call('get_sub_blocks', {'parentId': 'free'}) as List;
      expect(list.single['name'], 'Gym');

      final updated =
          await tools.call('update_sub_block', {'id': id, 'name': 'Workout'})
              as Map;
      expect(updated['name'], 'Workout');

      await tools.call('delete_sub_block', {'id': id});
      expect(r.subBlocks().of('free'), isEmpty);
    });

    test('add_sub_block outside the parent surfaces the error', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);
      expect(
        () => tools.call('add_sub_block', {
          'parentId': 'free', // 18:00–23:00
          'name': 'x',
          'start': '10:00', // outside Free time
          'end': '11:00',
        }),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });

    test('get_current_block reports the active sub-block', () async {
      final r = repo();
      final tools = DayDialTools(r, const AllowAllConsent(), clock: fixedClock);
      await tools.call('add_sub_block', {
        'parentId': 'free',
        'name': 'Gym',
        'start': '18:00',
        'end': '19:00',
      });
      final at1830 =
          await tools.call('get_current_block', {'now': '18:30'}) as Map;
      final detail = at1830['activeDetail'] as Map?;
      expect(detail?['name'], 'Gym');
      expect(detail?['minutesRemaining'], 30); // 18:30 -> 19:00

      // In a gap the block is active but there is no sub-block.
      final at2000 =
          await tools.call('get_current_block', {'now': '20:00'}) as Map;
      expect(at2000['activeDetail'], isNull);
    });

    test('delete_recurring_task and delete_sub_block are destructive', () {
      final specs = {for (final s in DayDialTools.specs) s.name: s};
      expect(specs['delete_recurring_task']!.destructive, isTrue);
      expect(specs['delete_sub_block']!.destructive, isTrue);
    });
  });

  group('get_calendar_events', () {
    test(
      'returns [] when no calendar is wired (local-first default)',
      () async {
        final tools = DayDialTools(
          repo(),
          CallbackConsent((_) async => true),
          clock: fixedClock,
        );
        final events = await tools.call('get_calendar_events') as List;
        expect(events, isEmpty);
      },
    );

    test('is a read tool — never touches the consent gate', () async {
      final gate = CallbackConsent((_) async => true);
      final tools = DayDialTools(repo(), gate, clock: fixedClock);
      await tools.call('get_calendar_events');
      expect(gate.seen, isEmpty);
    });

    test('surfaces overlay events for a date, expanding recurrence', () async {
      final calendar = InMemoryCalendarProvider([
        CalendarEvent(
          id: 'standup',
          sourceId: 'work',
          uid: 'standup',
          title: 'Standup',
          startTs: '2026-07-01T09:00:00',
          endTs: '2026-07-01T09:15:00',
          rrule: 'FREQ=DAILY',
          calendarName: 'Work',
        ),
      ]);
      final tools = DayDialTools(
        repo(),
        CallbackConsent((_) async => true),
        clock: fixedClock,
        calendar: calendar,
      );

      final events =
          await tools.call('get_calendar_events', {'date': '2026-07-03'})
              as List;
      expect(events, hasLength(1));
      final e = events.single as Map;
      expect(e['title'], 'Standup');
      expect(e['start'], '2026-07-03T09:00:00');
      expect(e['source'], 'work');
      expect(e['calendar'], 'Work');
      expect(e['allDay'], isFalse);
    });
  });
}
