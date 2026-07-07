import 'package:day_dial_core/day_dial_core.dart';
import 'package:http/http.dart' as http;

/// Fetches the raw iCalendar body for a source. Injectable so tests can supply
/// canned ICS with no network.
typedef IcsFetcher = Future<String> Function(CalendarSource source);

/// The app-side seam that turns configured [CalendarSource]s into a read-only
/// [CalendarProvider] (SPEC §12.1). Parsing + recurrence + overlay all live in
/// `core`; this only does the platform I/O (an HTTP GET of an ICS/CalDAV URL)
/// and hands the text to `icsToEvents`.
///
/// Local-first: a source that fails to fetch is skipped, never fatal — the
/// overlay simply omits it and the rest of the app is unaffected. The fetched
/// events are a disposable cache (never persisted into the CRDT doc); a fresh
/// [refresh] re-derives them.
class CalendarService {
  CalendarService({
    List<CalendarSource> sources = const [],
    IcsFetcher? fetcher,
  })  : _sources = [...sources],
        _fetch = fetcher ?? _httpFetch;

  final List<CalendarSource> _sources;
  final IcsFetcher _fetch;

  CalendarProvider _provider = InMemoryCalendarProvider(const []);

  /// The current overlay data. Empty until [refresh] runs.
  CalendarProvider get provider => _provider;

  List<CalendarSource> get sources => List.unmodifiable(_sources);

  /// Adds a source. Call [refresh] afterwards to pull its events.
  void addSource(CalendarSource source) => _sources.add(source);

  /// Removes the source with [id] (no-op if unknown).
  void removeSource(String id) => _sources.removeWhere((s) => s.id == id);

  /// Replaces the source sharing [CalendarSource.id] (e.g. after an edit or an
  /// enable/disable toggle). No-op if unknown.
  void replaceSource(CalendarSource source) {
    final i = _sources.indexWhere((s) => s.id == source.id);
    if (i != -1) _sources[i] = source;
  }

  /// The color to draw a source's events in, defaulting to a neutral calendar
  /// accent for an unknown id.
  String colorForSource(String sourceId) {
    for (final s in _sources) {
      if (s.id == sourceId) return s.colorHex;
    }
    return '#7C7CA8';
  }

  /// Re-fetches every enabled source and rebuilds the provider. Individual
  /// source failures are swallowed (see class doc); the returned list names the
  /// sources that failed, so the UI can surface a soft warning if it wants.
  Future<List<String>> refresh() async {
    final all = <CalendarEvent>[];
    final failed = <String>[];
    for (final s in _sources) {
      if (!s.enabled) continue;
      try {
        all.addAll(await _eventsFor(s));
      } catch (_) {
        failed.add(s.id);
      }
    }
    _provider = InMemoryCalendarProvider(all);
    return failed;
  }

  Future<List<CalendarEvent>> _eventsFor(CalendarSource s) async {
    switch (s.kind) {
      case CalendarSourceKind.caldav:
      case CalendarSourceKind.ics:
        return icsToEvents(await _fetch(s), sourceId: s.id);
      case CalendarSourceKind.device:
        // Reading the OS calendar needs a platform plugin (device_calendar),
        // wired on mobile in Phase 2. No-op on this seam.
        return const [];
    }
  }

  static Future<String> _httpFetch(CalendarSource s) async {
    final raw = s.url;
    if (raw == null) throw ArgumentError('Calendar source "${s.id}" has no URL');
    // `webcal://` is the ICS-subscription convention — it's plain HTTP(S).
    final url = raw.replaceFirst(RegExp('^webcal://'), 'https://');
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw http.ClientException('HTTP ${resp.statusCode} fetching "${s.id}"');
    }
    return resp.body;
  }
}
