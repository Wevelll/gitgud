import 'package:day_dial_core/day_dial_core.dart';

import 'seed.dart';
// Picks the persistent SQLite store on desktop/native, and a non-persistent
// in-memory store on web (which can't use dart:ffi). The web fallback keeps the
// golden rule "compiles on web" intact; a real IndexedDB store lands later.
import 'repository_factory_io.dart'
    if (dart.library.js_interop) 'repository_factory_web.dart';

/// Creates the app's repository for the current platform, seeded on first run
/// with the default day and demo tasks.
DayRepository createRepository() => openPlatformRepository();

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
