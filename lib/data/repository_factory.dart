import 'package:day_dial_core/day_dial_core.dart';

import 'persisted_day_repository.dart';
import 'seed.dart';
import 'synced_day_repository.dart';
// Picks the persistent SQLite store on desktop/native, and on web (which can't
// use dart:ffi) either the desktop hub or an IndexedDB-backed local day.
import 'repository_factory_io.dart'
    if (dart.library.js_interop) 'repository_factory_web.dart';

/// Creates the app's repository for the current platform, seeded on first run
/// with the default day and demo tasks. Async because the web build fetches
/// its initial state from the desktop hub over HTTP.
Future<DayRepository> createRepository() => openPlatformRepository();

/// Where a repository's data actually lives.
///
/// The app opens whatever it can reach (SPEC §8) and the outcome is invisible
/// otherwise — most importantly [ephemeral], where the user would lose their
/// day on reload with no warning at all.
enum StorageMode {
  /// A local database on this machine — the desktop's SQLite file.
  device('Saved on this device', 'Your day is stored locally in ~/.day_dial.'),

  /// The browser's IndexedDB. Durable, but per-browser and per-origin.
  browser(
    'Saved in this browser',
    'Your day is stored in this browser. Run the desktop app to sync instead.',
  ),

  /// Mirrored to a desktop hub over HTTP; the desktop owns the data.
  hub(
    'Synced to the desktop app',
    'Edits here are written straight through to the desktop app.',
  ),

  /// Nothing is being written — reloading loses everything. Happens when the
  /// browser denies storage (private browsing, some embedded webviews).
  ephemeral(
    'Not being saved',
    'This browser is blocking local storage, so changes will be lost when the '
        'page reloads.',
  );

  const StorageMode(this.label, this.detail);

  /// Short label for a chip or tooltip.
  final String label;

  /// A sentence explaining what it means, for a tap/hover.
  final String detail;
}

/// Classifies [repo] for display. Platform-agnostic: the two wrapper types are
/// pure Dart, and anything else is a real local database.
StorageMode storageModeOf(DayRepository repo) => switch (repo) {
  SyncedDayRepository() => StorageMode.hub,
  PersistedDayRepository() => StorageMode.browser,
  // The in-memory store is only ever reached as the "storage is blocked"
  // fallback; every persistent store is one of the cases above or a database.
  InMemoryDayRepository() => StorageMode.ephemeral,
  _ => StorageMode.device,
};

/// Ensures the demo tasks and habits exist the first time a store is created (a
/// fresh store has none). Shared by both platform factories.
void seedTasksIfEmpty(DayRepository repo) {
  if (repo.tasks().isEmpty) {
    for (final t in demoTasks()) {
      repo.addRecurringTask(
        label: t.label,
        recurrence: t.recurrence,
        colorHex: t.colorHex,
      );
    }
  }
  if (repo.habits().isEmpty) {
    for (final h in demoHabits()) {
      repo.addHabit(
        label: h.label,
        colorHex: h.colorHex,
        polarity: h.polarity,
        dailyTarget: h.target,
      );
    }
  }
}
