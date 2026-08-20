/// Id generation for records a repository mints (segments, tasks, logs, …).
///
/// The ids only need to be unique *within one user's store* — they are never
/// exchanged with a server or another user — but they must stay unique **across
/// restarts**: a store that reloads persisted state and then restarts a plain
/// `1, 2, 3` counter would hand out ids that already exist on disk.
///
/// Platform-agnostic on purpose: both the SQLite store (desktop) and the
/// IndexedDB-backed web store need exactly this, and `core` is where the two
/// meet.
library;

/// A generator of store-unique ids: a per-open time base plus a counter, so
/// two runs of the same app never mint the same id (the base differs) and one
/// run never repeats itself (the counter increments).
///
/// Pass [seed] to make it deterministic in tests.
String Function() uniqueIdFactory({String? seed}) {
  var n = 0;
  final base = seed ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return () => '$base-${n++}';
}
