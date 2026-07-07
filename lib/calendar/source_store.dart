import 'package:day_dial_core/day_dial_core.dart';

// Platform-split persistence for the calendar *source list* (SPEC §12.1): the
// subscriptions themselves are small config, distinct from the disposable event
// cache. Desktop writes a JSON file; web is session-only for now (a no-op store)
// pending an IndexedDB / hub-sync path. Mirrors the notifier / exporter
// conditional-import idiom.
//
// Note: the convention-correct end state is a `calendar_sources` row set in the
// store layer (SPEC §5); this file store is an interim, desktop-durable step.
import 'source_store_io.dart'
    if (dart.library.js_interop) 'source_store_web.dart';

/// Loads and saves the configured [CalendarSource] list.
abstract interface class CalendarSourceStore {
  Future<List<CalendarSource>> load();
  Future<void> save(List<CalendarSource> sources);
}

/// The current platform's [CalendarSourceStore]. [path] overrides the default
/// location (used by tests); ignored where it doesn't apply (web).
CalendarSourceStore createCalendarSourceStore({String? path}) =>
    makeCalendarSourceStore(path: path);

/// A store that persists nothing — the default when none is wired, so a
/// [CalendarService] created without a store behaves exactly as before.
class NullCalendarSourceStore implements CalendarSourceStore {
  const NullCalendarSourceStore();

  @override
  Future<List<CalendarSource>> load() async => const [];

  @override
  Future<void> save(List<CalendarSource> sources) async {}
}
