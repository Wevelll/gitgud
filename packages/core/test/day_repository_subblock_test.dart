import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  // Sleep 23:00–09:00, Work 09:00–18:00, Free 18:00–23:00.
  DayProfile profile() => DayProfile.ring(
        id: 'weekday',
        name: 'Weekday',
        isDefault: true,
        segmentIds: const ['sleep', 'work', 'free'],
        spans: const [
          (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
          (startMin: 540, name: 'Work', colorHex: '#3E7CB1'),
          (startMin: 1080, name: 'Free', colorHex: '#6FA85B'),
        ],
      );

  InMemoryDayRepository repo() => InMemoryDayRepository(profiles: [profile()]);

  Segment addGym(InMemoryDayRepository r) => r.addSubBlock(
        parentId: 'free',
        name: 'Gym',
        colorHex: '#abc',
        startMin: 1080, // 18:00
        endMin: 1140, // 19:00
      );

  group('sub-block CRUD (in-memory)', () {
    test('add and read back grouped by parent', () {
      final r = repo();
      addGym(r);
      r.addSubBlock(
        parentId: 'free',
        name: 'Read',
        colorHex: '#def',
        startMin: 1200,
        endMin: 1260,
      );
      expect(r.subBlocks().of('free').map((s) => s.name), ['Gym', 'Read']);
    });

    test('adding outside the parent throws', () {
      expect(
        () => repo().addSubBlock(
          parentId: 'free',
          name: 'x',
          colorHex: '#abc',
          startMin: 600, // 10:00 — inside Work, not Free
          endMin: 660,
        ),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });

    test('adding an overlapping sibling throws', () {
      final r = repo();
      r.addSubBlock(
        parentId: 'free',
        name: 'a',
        colorHex: '#abc',
        startMin: 1080,
        endMin: 1200,
      );
      expect(
        () => r.addSubBlock(
          parentId: 'free',
          name: 'b',
          colorHex: '#abc',
          startMin: 1140,
          endMin: 1260,
        ),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });

    test('adding under an unknown parent throws StateError', () {
      expect(
        () => repo().addSubBlock(
          parentId: 'nope',
          name: 'x',
          colorHex: '#abc',
          startMin: 1080,
          endMin: 1140,
        ),
        throwsStateError,
      );
    });

    test('update label and bounds', () {
      final r = repo();
      final gym = addGym(r);
      final up = r.updateSubBlock(gym.id, name: 'Yoga', endMin: 1170);
      expect(up.name, 'Yoga');
      expect(up.endMin, 1170);
      expect(r.subBlocks().of('free').single.name, 'Yoga');
    });

    test('updating out of the parent throws', () {
      final r = repo();
      final gym = addGym(r);
      expect(
        () => r.updateSubBlock(gym.id, endMin: 1400), // past Free's 23:00 end
        throwsA(isA<InvalidSubBlockException>()),
      );
    });

    test('delete a sub-block, and unknown id throws', () {
      final r = repo();
      final gym = addGym(r);
      r.deleteSubBlock(gym.id);
      expect(r.subBlocks().of('free'), isEmpty);
      expect(() => r.deleteSubBlock('nope'), throwsStateError);
    });
  });

  group('cascade on parent edit', () {
    test('resizing a parent clips an overhanging sub-block', () {
      final r = repo();
      addGym(r); // 18:00–19:00
      r.updateBlock('free', startMin: 1110); // Free start 18:00 → 18:30
      final k = r.subBlocks().of('free').single;
      expect(k.startMin, 1110); // clipped to the new edge
      expect(k.endMin, 1140);
    });

    test('resizing a parent drops a sub-block that no longer fits', () {
      final r = repo();
      addGym(r); // 18:00–19:00
      r.addSubBlock(
        parentId: 'free',
        name: 'Read',
        colorHex: '#def',
        startMin: 1200,
        endMin: 1260,
      );
      r.updateBlock('free', startMin: 1140); // Free start → 19:00; Gym is gone
      expect(r.subBlocks().of('free').map((s) => s.name), ['Read']);
    });

    test('deleting a parent block drops its sub-blocks', () {
      final r = repo();
      addGym(r);
      r.deleteBlock('free');
      expect(r.subBlocks().of('free'), isEmpty);
    });
  });

  group('serialization', () {
    test('sub-blocks survive a snapshot JSON round-trip and rehydrate', () {
      final r = repo();
      addGym(r);
      final restored = DaySnapshot.fromJson(r.snapshot().toJson());
      expect(restored.subBlocks['free']!.single.name, 'Gym');

      final r2 = InMemoryDayRepository.fromSnapshot(restored);
      expect(r2.subBlocks().of('free').single.name, 'Gym');
    });
  });
}
