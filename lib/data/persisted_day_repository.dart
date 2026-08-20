import 'package:day_dial_core/day_dial_core.dart';

import 'mirrored_repository.dart';

/// Saves a whole snapshot to some backing store. Async because the browser's
/// IndexedDB is (the desktop's SQLite is not, and doesn't need this class).
typedef SnapshotSink = Future<void> Function(DaySnapshot snapshot);

/// A repository that mirrors every edit into an asynchronous local store — the
/// web build's persistence (SPEC §8: a real local store for the browser, so the
/// page is usable with no desktop hub reachable and survives a reload).
///
/// Coalescing, error handling, and the `idle` hook all come from
/// [MirroredDayRepository]; this only says *where* the snapshot goes.
class PersistedDayRepository extends MirroredDayRepository {
  PersistedDayRepository({
    required InMemoryDayRepository cache,
    required this.save,
  }) : super(cache);

  final SnapshotSink save;

  @override
  Future<void> mirror(DaySnapshot snapshot) => save(snapshot);
}
