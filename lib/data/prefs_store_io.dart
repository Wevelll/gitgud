import 'dart:convert';
import 'dart:io';

import 'app_dirs_io.dart';
import 'prefs_store.dart';

/// Desktop/mobile prefs — a small JSON map in the app-data directory.
PrefsStore makePrefsStore() => IoPrefsStore();

class IoPrefsStore implements PrefsStore {
  IoPrefsStore([this._fixedPath]);

  /// Test override; defaults to `<app-data>/prefs.json`.
  final String? _fixedPath;

  Future<File> _file() async =>
      File(_fixedPath ?? '${(await appDataDirectory()).path}/prefs.json');

  Future<Map<String, Object?>> _load() async {
    final file = await _file();
    if (!file.existsSync()) return {};
    try {
      final data = jsonDecode(await file.readAsString());
      return data is Map ? data.cast<String, Object?>() : {};
    } catch (_) {
      // A corrupt prefs file must not brick the app — start clean.
      return {};
    }
  }

  @override
  Future<String?> read(String key) async => (await _load())[key] as String?;

  @override
  Future<void> write(String key, String value) async {
    final map = await _load()
      ..[key] = value;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(map));
  }
}
