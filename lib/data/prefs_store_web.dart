import 'prefs_store.dart';

/// Web prefs — session-only. CLAUDE.md bans ad-hoc localStorage; until the
/// IndexedDB store layer lands, the web companion simply follows the OS theme
/// on each load and remembers a toggle only for the session.
PrefsStore makePrefsStore() => _MemoryPrefsStore();

class _MemoryPrefsStore implements PrefsStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}
