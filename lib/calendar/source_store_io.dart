import 'dart:convert';
import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';

import '../data/app_dirs_io.dart';
import 'source_store.dart';

/// Desktop/mobile store — persists the source list as JSON in the platform's
/// app-data directory (`~/.day_dial/calendar_sources.json` on desktop).
CalendarSourceStore makeCalendarSourceStore({String? path}) =>
    IoCalendarSourceStore(path);

class IoCalendarSourceStore implements CalendarSourceStore {
  IoCalendarSourceStore([this._fixedPath]);

  /// Test override; the default is resolved per platform on first use (the
  /// mobile app-dir lookup is async, so it can't happen in the constructor).
  final String? _fixedPath;

  Future<String> _path() async =>
      _fixedPath ?? '${(await appDataDirectory()).path}/calendar_sources.json';

  @override
  Future<List<CalendarSource>> load() async {
    final file = File(await _path());
    if (!file.existsSync()) return const [];
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return const [];
      return [
        for (final e in data)
          CalendarSource.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      // A corrupt file must not brick the app (local-first) — start clean.
      return const [];
    }
  }

  @override
  Future<void> save(List<CalendarSource> sources) async {
    final file = File(await _path());
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final s in sources) s.toJson()]));
  }
}
