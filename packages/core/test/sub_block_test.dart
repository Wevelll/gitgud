import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  Segment seg(String id, int start, int end) =>
      Segment(id: id, name: id, colorHex: '#fff', startMin: start, endMin: end);

  // A non-wrapping parent: Free time 18:00–23:00.
  final free = seg('free', 1080, 1380);
  // A midnight-wrapping parent: Sleep 23:00–07:00 (duration 480).
  final sleep = seg('sleep', 1380, 420);

  group('parentContainsSubBlock (non-wrapping parent)', () {
    test('child flush to the start is inside', () {
      expect(parentContainsSubBlock(free, seg('c', 1080, 1140)), isTrue);
    });
    test('child flush to the end is inside', () {
      expect(parentContainsSubBlock(free, seg('c', 1320, 1380)), isTrue);
    });
    test('child strictly inside is inside', () {
      expect(parentContainsSubBlock(free, seg('c', 1140, 1200)), isTrue);
    });
    test('child starting at the parent end is out', () {
      expect(parentContainsSubBlock(free, seg('c', 1380, 1400)), isFalse);
    });
    test('child before the parent start is out', () {
      expect(parentContainsSubBlock(free, seg('c', 1020, 1080)), isFalse);
    });
    test('child overhanging the end is out', () {
      expect(parentContainsSubBlock(free, seg('c', 1350, 1400)), isFalse);
    });
  });

  group('parentContainsSubBlock (midnight-wrapping parent)', () {
    test('child after midnight is inside', () {
      expect(parentContainsSubBlock(sleep, seg('c', 0, 60)), isTrue);
    });
    test('child straddling midnight is inside', () {
      expect(parentContainsSubBlock(sleep, seg('c', 1410, 30)), isTrue);
    });
    test('child flush to the wrapping end (…07:00) is inside', () {
      expect(parentContainsSubBlock(sleep, seg('c', 360, 420)), isTrue);
    });
    test('child overhanging the wrapping end is out', () {
      expect(parentContainsSubBlock(sleep, seg('c', 380, 440)), isFalse);
    });
    test('child in the daytime (outside sleep) is out', () {
      expect(parentContainsSubBlock(sleep, seg('c', 600, 660)), isFalse);
    });
  });

  group('validateSubBlocks', () {
    test('sparse, non-overlapping children are valid', () {
      expect(
        () => validateSubBlocks(
          free,
          [seg('a', 1080, 1140), seg('b', 1200, 1260)],
        ),
        returnsNormally,
      );
    });
    test('touching children (shared boundary) are valid', () {
      expect(
        () => validateSubBlocks(
          free,
          [seg('a', 1080, 1140), seg('b', 1140, 1200)],
        ),
        returnsNormally,
      );
    });
    test('overlapping children throw', () {
      expect(
        () => validateSubBlocks(
          free,
          [seg('a', 1080, 1200), seg('b', 1140, 1260)],
        ),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });
    test('duplicate ids throw', () {
      expect(
        () => validateSubBlocks(
          free,
          [seg('a', 1080, 1140), seg('a', 1200, 1260)],
        ),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });
    test('zero-length child throws', () {
      expect(
        () => validateSubBlocks(free, [seg('a', 1100, 1100)]),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });
    test('child outside the parent throws', () {
      expect(
        () => validateSubBlocks(free, [seg('a', 600, 660)]),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });
    test('valid children inside a wrapping parent, incl. a straddle', () {
      expect(
        () => validateSubBlocks(
          sleep,
          [seg('night', 1410, 30), seg('early', 120, 180)],
        ),
        returnsNormally,
      );
    });
  });

  group('activeSubBlockAt', () {
    final kids = [seg('a', 1080, 1140), seg('b', 1200, 1260)];
    test('minute inside a child returns it', () {
      expect(activeSubBlockAt(free, kids, 1100)?.id, 'a');
      expect(activeSubBlockAt(free, kids, 1230)?.id, 'b');
    });
    test('minute in a gap returns null', () {
      expect(activeSubBlockAt(free, kids, 1170), isNull);
    });
    test('a straddling child is found across midnight', () {
      final night = [seg('night', 1410, 30)];
      expect(activeSubBlockAt(sleep, night, 0)?.id, 'night'); // 00:00
      expect(activeSubBlockAt(sleep, night, 1425)?.id, 'night'); // 23:45
      expect(activeSubBlockAt(sleep, night, 120), isNull); // 02:00, a gap
    });
  });

  group('clipToParent', () {
    test('child already inside is returned unchanged', () {
      expect(clipToParent(free, seg('c', 1140, 1200)), seg('c', 1140, 1200));
    });
    test('child overhanging the end is clipped to the end', () {
      // Parent shrank to 18:00–20:00; child 19:00–21:00 → 19:00–20:00.
      final shrunk = seg('free', 1080, 1200);
      expect(clipToParent(shrunk, seg('c', 1140, 1260)), seg('c', 1140, 1200));
    });
    test('child overhanging the start is clipped to the start', () {
      // Parent shrank to 19:00–23:00; child 18:00–20:00 → 19:00–20:00.
      final shrunk = seg('free', 1140, 1380);
      expect(clipToParent(shrunk, seg('c', 1080, 1200)), seg('c', 1140, 1200));
    });
    test('child no longer overlapping is dropped (null)', () {
      final shrunk = seg('free', 1080, 1200); // 18:00–20:00
      expect(clipToParent(shrunk, seg('c', 1260, 1320)), isNull); // 21–22
    });
    test('clips inside a wrapping parent', () {
      // Sleep shrinks to 00:00–07:00; a 23:30–00:30 child → 00:00–00:30.
      final shrunk = seg('sleep', 0, 420);
      expect(clipToParent(shrunk, seg('c', 1410, 30)), seg('c', 0, 30));
    });
  });

  group('reconcileSubBlocks', () {
    DayProfile profile(int freeStart) => DayProfile.ring(
          id: 'weekday',
          name: 'Weekday',
          segmentIds: const ['sleep', 'free'],
          spans: [
            (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
            (startMin: freeStart, name: 'Free', colorHex: '#6FA85B'),
          ],
        );

    test('clips children when their parent shrank, drops the vanished', () {
      // Free is 18:00–23:00, holding gym 18:00–19:00 and read 22:00–23:00.
      final plan = {
        'free': [seg('gym', 1080, 1140), seg('read', 1320, 1380)],
      };
      // Free now starts at 20:00 (Sleep grew back): gym is gone, read stays.
      final out = reconcileSubBlocks(profile(1200), plan);
      expect(out['free']!.map((s) => s.id), ['read']);
    });

    test('drops all sub-blocks of a parent that no longer exists', () {
      final plan = {
        'lunch': [seg('walk', 1080, 1140)],
      };
      expect(reconcileSubBlocks(profile(1080), plan), isEmpty);
    });
  });

  group('SubBlockPlan', () {
    DayProfile profile() => DayProfile.ring(
          id: 'weekday',
          name: 'Weekday',
          isDefault: true,
          segmentIds: const ['sleep', 'morning', 'free'],
          spans: const [
            (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
            (startMin: 420, name: 'Morning', colorHex: '#C98A3E'),
            (startMin: 1080, name: 'Free', colorHex: '#6FA85B'),
          ],
        );

    test('validateAgainst passes for a legal overlay', () {
      final plan = SubBlockPlan({
        'free': [seg('gym', 1080, 1140), seg('read', 1200, 1260)],
      });
      expect(() => plan.validateAgainst(profile()), returnsNormally);
    });

    test('validateAgainst rejects an unknown parent id', () {
      final plan = SubBlockPlan({
        'lunchtime': [seg('walk', 1080, 1140)],
      });
      expect(
        () => plan.validateAgainst(profile()),
        throwsA(isA<InvalidSubBlockException>()),
      );
    });

    test('contextAt returns the parent and the active child', () {
      final plan = SubBlockPlan({
        'free': [seg('gym', 1080, 1140)],
      });
      final inGym = plan.contextAt(profile(), 1100);
      expect(inGym.parent.id, 'free');
      expect(inGym.child?.id, 'gym');

      final inGap = plan.contextAt(profile(), 1300);
      expect(inGap.parent.id, 'free');
      expect(inGap.child, isNull);

      final inSleep = plan.contextAt(profile(), 0);
      expect(inSleep.parent.id, 'sleep');
      expect(inSleep.child, isNull); // sleep has no sub-blocks
    });

    test('empty plan is inert', () {
      const plan = SubBlockPlan.empty();
      expect(plan.isEmpty, isTrue);
      expect(plan.of('free'), isEmpty);
      expect(() => plan.validateAgainst(profile()), returnsNormally);
    });
  });
}
