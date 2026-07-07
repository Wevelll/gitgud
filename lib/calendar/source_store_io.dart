import 'dart:convert';
import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';

import 'source_store.dart';

/// Desktop/native store — persists the source list as JSON under the user's
/// config dir (`$HOME/.day_dial/calendar_sources.json`).
CalendarSourceStore makeCalendarSourceStore({String? path}) =>
    IoCalendarSourceStore(path);

class IoCalendarSourceStore implements CalendarSourceStore {
  IoCalendarSourceStore([String? path]) : _path = path ?? _defaultPath();

  final String _path;

  @override
  Future<List<CalendarSource>> load() async {
    final file = File(_path);
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
    final file = File(_path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final s in sources) s.toJson()]),
    );
  }

  static String _defaultPath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final base = home ?? Directory.systemTemp.path;
    return '$base/.day_dial/calendar_sources.json';
  }
}
