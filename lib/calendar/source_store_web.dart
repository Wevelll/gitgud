import 'package:day_dial_core/day_dial_core.dart';

import '../data/browser_store.dart';
import 'source_store.dart';

/// Web store — the subscription list as a JSON record in IndexedDB, alongside
/// the day itself (SPEC §12.1).
///
/// Without this the browser forgot every calendar on reload, which made the
/// Calendars screen busywork rather than setup. If IndexedDB is unavailable
/// (private browsing, some embedded webviews) it degrades to remembering
/// nothing rather than failing — the day still works, which is the local-first
/// bargain.
CalendarSourceStore makeCalendarSourceStore({String? path}) =>
    WebCalendarSourceStore();

class WebCalendarSourceStore implements CalendarSourceStore {
  Future<BrowserJsonStore>? _opening;

  /// Opened once and reused; a failure is retried on the next call rather than
  /// cached, so a transient block doesn't disable storage for the session.
  Future<BrowserJsonStore> _store() {
    final pending = _opening ??= BrowserJsonStore.open();
    return pending.catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  @override
  Future<List<CalendarSource>> load() async {
    try {
      final data = await (await _store()).read(
        BrowserJsonStore.calendarSourcesKey,
      );
      if (data is! List) return const [];
      return [
        for (final e in data)
          CalendarSource.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<CalendarSource> sources) async {
    try {
      await (await _store()).write(BrowserJsonStore.calendarSourcesKey, [
        for (final s in sources) s.toJson(),
      ]);
    } catch (_) {
      // Local-first: losing persistence must not take the session down.
    }
  }
}
