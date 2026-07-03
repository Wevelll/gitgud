import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

/// Simple even quarters: A/B/C/D, 6h each, ids A..D.
DayProfile quarters() => DayProfile.ring(
      id: 'p',
      name: 'p',
      segmentIds: const ['A', 'B', 'C', 'D'],
      spans: const [
        (startMin: 0, name: 'A', colorHex: '#a'), // 00:00
        (startMin: 360, name: 'B', colorHex: '#b'), // 06:00
        (startMin: 720, name: 'C', colorHex: '#c'), // 12:00
        (startMin: 1080, name: 'D', colorHex: '#d'), // 18:00
      ],
    );

int sumDur(DayProfile p) => p.segments.fold(0, (acc, s) => acc + s.durationMin);

void expectGaplessRing(DayProfile p) {
  expect(sumDur(p), 1440, reason: 'durations must sum to 1440');
  for (var i = 0; i < p.segments.length; i++) {
    final next = p.segments[(i + 1) % p.segments.length];
    expect(p.segments[i].endMin, next.startMin, reason: 'no gaps');
  }
  final ids = p.segments.map((s) => s.id).toList();
  expect(ids.toSet().length, ids.length, reason: 'ids stay unique');
}

void main() {
  group('addBlock', () {
    test('inserted mid-segment splits the host into two', () {
      final r = quarters().addBlock(
          id: 'X', name: 'X', colorHex: '#x', startMin: 480, endMin: 600);
      expectGaplessRing(r);
      final x = r.segments.firstWhere((s) => s.id == 'X');
      expect(x.startMin, 480);
      expect(x.endMin, 600);
      // B is split into two 120m pieces around X.
      final bPieces = r.segments.where((s) => s.name == 'B').toList();
      expect(bPieces.length, 2);
      expect(bPieces.every((s) => s.durationMin == 120), isTrue);
    });

    test('overwrites across a boundary, trimming both neighbors', () {
      final r = quarters().addBlock(
          id: 'X', name: 'X', colorHex: '#x', startMin: 600, endMin: 780);
      expectGaplessRing(r);
      expect(r.segments.firstWhere((s) => s.id == 'B').endMin, 600);
      expect(r.segments.firstWhere((s) => s.id == 'C').startMin, 780);
    });

    test('a wrapping block is placed correctly', () {
      final r = quarters().addBlock(
          id: 'X', name: 'X', colorHex: '#x', startMin: 1380, endMin: 120);
      expectGaplessRing(r);
      final x = r.segments.firstWhere((s) => s.id == 'X');
      expect(x.wrapsMidnight, isTrue);
      expect(x.durationMin, 180);
    });

    test('rejects a block that starves a neighbor below 15m', () {
      // Leaves A with only 0..10 = 10m.
      expect(
        () => quarters().addBlock(
            id: 'X', name: 'X', colorHex: '#x', startMin: 10, endMin: 360),
        throwsA(isA<InvalidProfileException>()),
      );
    });

    test('rejects a duplicate id and an out-of-range length', () {
      expect(
        () => quarters().addBlock(
            id: 'B', name: 'dup', colorHex: '#x', startMin: 10, endMin: 40),
        throwsA(isA<InvalidProfileException>()),
      );
      expect(
        () => quarters().addBlock(
            id: 'X', name: 'X', colorHex: '#x', startMin: 0, endMin: 1430),
        throwsA(isA<InvalidProfileException>()),
      );
    });
  });

  group('deleteBlock', () {
    test('hands the span to the preceding neighbor', () {
      final r = quarters().deleteBlock('B');
      expectGaplessRing(r);
      expect(r.segments.length, 3);
      expect(r.segments.any((s) => s.id == 'B'), isFalse);
      // A absorbed B: now 0..720.
      final a = r.segments.firstWhere((s) => s.id == 'A');
      expect(a.startMin, 0);
      expect(a.endMin, 720);
    });

    test('deleting the first block merges across midnight into the last', () {
      final r = quarters().deleteBlock('A');
      expectGaplessRing(r);
      final d = r.segments.firstWhere((s) => s.id == 'D');
      expect(d.wrapsMidnight, isTrue); // 1080..360
      expect(d.endMin, 360);
    });

    test('rejects deleting down to a single segment', () {
      final two = DayProfile.ring(
        id: 'p',
        name: 'p',
        segmentIds: const ['A', 'B'],
        spans: const [
          (startMin: 0, name: 'A', colorHex: '#a'),
          (startMin: 720, name: 'B', colorHex: '#b'),
        ],
      );
      expect(
          () => two.deleteBlock('A'), throwsA(isA<InvalidProfileException>()));
    });

    test('rejects an unknown id', () {
      expect(() => quarters().deleteBlock('Z'),
          throwsA(isA<InvalidProfileException>()));
    });
  });

  group('updateBlock', () {
    test('rename/recolor keeps geometry', () {
      final r = quarters().updateBlock('C', name: 'Cafe', colorHex: '#new');
      final c = r.segments.firstWhere((s) => s.id == 'C');
      expect(c.name, 'Cafe');
      expect(c.colorHex, '#new');
      expect(c.startMin, 720);
      expect(c.endMin, 1080);
      expectGaplessRing(r);
    });

    test('resizing an edge moves the shared boundary, no stray pieces', () {
      final r = quarters().updateBlock('B', endMin: 600); // shrink B's end
      expectGaplessRing(r);
      expect(r.segments.length, 4); // no split
      expect(r.segments.firstWhere((s) => s.id == 'B').endMin, 600);
      expect(r.segments.firstWhere((s) => s.id == 'C').startMin, 600);
    });

    test('moving both edges resizes on both sides', () {
      final r = quarters().updateBlock('B', startMin: 300, endMin: 600);
      expectGaplessRing(r);
      final b = r.segments.firstWhere((s) => s.id == 'B');
      expect(b.startMin, 300);
      expect(b.endMin, 600);
      expect(r.segments.firstWhere((s) => s.id == 'A').endMin, 300);
    });

    test('rejects an edge move that crosses past the adjacent segment', () {
      // Pull B's start back past A entirely (A only 360m of room).
      expect(() => quarters().updateBlock('B', startMin: 1000),
          throwsA(isA<InvalidProfileException>()));
    });
  });
}
