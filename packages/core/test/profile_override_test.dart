import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  DayProfile weekday() => DayProfile.fromDurations(
        id: 'weekday',
        name: 'Weekday',
        isDefault: true,
        activeDaysMask: 31,
        segmentIds: const ['sleep', 'work', 'free'],
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Work', colorHex: '#3E7CB1', minutes: 480),
          (name: 'Free', colorHex: '#6FA85B', minutes: 480),
        ],
      );

  InMemoryDayRepository repo() => InMemoryDayRepository(profiles: [weekday()]);

  final mon = CivilDate.parse('2026-07-06');

  test('overrideForDate makes an independent, idempotent per-date copy', () {
    final r = repo();
    final o = r.overrideForDate(mon);

    expect(o.forDate, '2026-07-06');
    expect(o.segments.length, 3);
    // Fresh segment ids (not the template's).
    expect(o.segments.map((s) => s.id), isNot(contains('sleep')));
    expect(r.profileForDate(mon).id, o.id); // the override wins resolution
    expect(r.overrideForDate(mon).id, o.id); // idempotent
    expect(r.templateForDate(mon).id, 'weekday'); // template still reachable
  });

  test('editing the override leaves the template untouched', () {
    final r = repo();
    final o = r.overrideForDate(mon);
    r.switchProfile(o.id);
    r.updateBlock(o.segments.first.id, name: 'Lie-in');

    expect(r.profileForDate(mon).segments.first.name, 'Lie-in');
    expect(r.templateForDate(mon).segments.first.name, 'Sleep');
  });

  test('the override inherits the template sub-blocks, independently', () {
    final r = repo();
    r.addSubBlock(
      parentId: 'work',
      name: 'Standup',
      colorHex: '#abc',
      startMin: 480,
      endMin: 510,
    );
    final templateSubId = r.subBlocks().of('work').single.id;

    final o = r.overrideForDate(mon);
    final workOverride = o.segments.firstWhere((s) => s.name == 'Work');
    final inherited = r.subBlocks().of(workOverride.id);

    expect(inherited.single.name, 'Standup'); // inherited
    expect(inherited.single.id, isNot(templateSubId)); // but a fresh copy
    expect(r.subBlocks().of('work').single.name, 'Standup'); // template kept
  });

  test('resetDate discards the override and reverts to the template', () {
    final r = repo();
    final o = r.overrideForDate(mon);
    r.switchProfile(o.id);
    r.addSubBlock(
      parentId: o.segments.first.id,
      name: 'x',
      colorHex: '#abc',
      startMin: 0,
      endMin: 30,
    );

    r.resetDate(mon);

    expect(r.profileForDate(mon).id, 'weekday'); // back to the template
    expect(r.subBlocks().of(o.segments.first.id), isEmpty); // its detail purged
    expect(r.activeProfile().id, 'weekday'); // active no longer dangles
  });
}
