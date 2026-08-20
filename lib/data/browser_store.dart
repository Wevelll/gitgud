import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The web build's local persistence: JSON records in **IndexedDB** (CLAUDE.md
/// — never `localStorage`; it's synchronous, small, and string-only, and
/// browsers evict it more readily).
///
/// One database, one object store, a record per key — the day's snapshot under
/// one key, the calendar subscriptions under another. Everything here is a few
/// kilobytes of JSON, so there's nothing to gain from row-per-entity storage,
/// and a whole-record write means a save is atomic: the page either has the
/// previous state or the new one, never half of each.
///
/// This is the browser's answer to the desktop's SQLite file plus its config
/// directory, and it's what makes the web build usable with no hub reachable
/// (SPEC §8).
class BrowserJsonStore {
  BrowserJsonStore._(this._db);

  final web.IDBDatabase _db;

  static const _dbName = 'day_dial';
  static const _storeName = 'state';
  static const _version = 1;

  /// The day's full [DaySnapshot].
  static const snapshotKey = 'snapshot';

  /// The configured calendar subscriptions (SPEC §12.1).
  static const calendarSourcesKey = 'calendar_sources';

  /// Opens (creating on first run) the database. Throws if IndexedDB is
  /// unavailable — private-browsing modes and embedded webviews do block it,
  /// and the caller decides what to fall back to.
  static Future<BrowserJsonStore> open() async {
    final request = web.window.indexedDB.open(_dbName, _version);
    request.onupgradeneeded = (web.Event _) {
      final db = request.result! as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;
    final db = await _completed(request);
    return BrowserJsonStore._(db! as web.IDBDatabase);
  }

  /// Reads the JSON stored under [key], or null when nothing is stored or the
  /// record is unreadable — a corrupt record must not brick the app, so a parse
  /// failure is treated as "nothing saved".
  Future<Object?> read(String key) async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final value = await _completed(tx.objectStore(_storeName).get(key.toJS));
    if (value == null) return null;
    try {
      return jsonDecode((value as JSString).toDart);
    } catch (_) {
      return null;
    }
  }

  /// Writes [value] (anything `jsonEncode` accepts) under [key], replacing
  /// whatever was there.
  Future<void> write(String key, Object? value) async {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    final json = jsonEncode(value);
    await _completed(tx.objectStore(_storeName).put(json.toJS, key.toJS));
  }

  /// Bridges an [web.IDBRequest] to a [Future]. Every IndexedDB call is a
  /// request object that later fires `success` or `error`; this is the one
  /// place that translation happens.
  static Future<JSAny?> _completed(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = (web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }.toJS;
    request.onerror = (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB request failed: ${request.error?.message}'),
        );
      }
    }.toJS;
    return completer.future;
  }
}
