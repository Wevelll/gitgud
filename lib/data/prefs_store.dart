// Same conditional-import idiom as repository_factory / notifier: a real
// file on desktop/mobile, an in-memory stub on web.
import 'prefs_store_io.dart'
    if (dart.library.js_interop) 'prefs_store_web.dart';

/// Tiny key-value store for UI-only preferences (currently the theme mode).
///
/// Deliberately not part of the repository: this is device-local chrome, not
/// user data — it must never enter the CRDT document or sync.
abstract interface class PrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// The current platform's [PrefsStore].
PrefsStore createPrefsStore() => makePrefsStore();
