import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:web/web.dart' as web;

/// The web build's local persistence: a [DaySnapshot] kept in **IndexedDB**
/// (CLAUDE.md — never `localStorage`; it's synchronous, small, and string-only,
/// and browsers evict it more readily).
///
/// One database, one object store, one record under a fixed key. The whole day
/// is a few kilobytes of JSON, so there's nothing to gain from row-per-entity
/// storage — and a single record means a save is atomic: the page either has
/// the previous state or the new one, never half of each.
///
/// This is the browser's answer to the desktop's SQLite file, and it's what
/// makes the web build usable with no hub reachable (SPEC §8).
class BrowserSnapshotStore {
  BrowserSnapshotStore._(this._db);

  final web.IDBDatabase _db;

  static const _dbName = 'day_dial';
  static const _storeName = 'state';
  static const _key = 'snapshot';
  static const _version = 1;

  /// Opens (creating on first run) the database. Throws if IndexedDB is
  /// unavailable — private-browsing modes and embedded webviews do block it,
  /// and the caller decides what to fall back to.
  static Future<BrowserSnapshotStore> open() async {
    final request = web.window.indexedDB.open(_dbName, _version);
    request.onupgradeneeded = (web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;
    final db = await _completed(request);
    return BrowserSnapshotStore._(db! as web.IDBDatabase);
  }

  /// Reads the stored snapshot, or null on first run (nothing saved yet) or if
  /// the record is unreadable — a corrupt record must not brick the app, so a
  /// parse failure is treated as "no saved state".
  Future<DaySnapshot?> read() async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final value = await _completed(tx.objectStore(_storeName).get(_key.toJS));
    if (value == null) return null;
    try {
      final json = (jsonDecode((value as JSString).toDart) as Map)
          .cast<String, Object?>();
      return DaySnapshot.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Writes [snapshot], replacing whatever was there.
  Future<void> write(DaySnapshot snapshot) async {
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    final json = jsonEncode(snapshot.toJson());
    await _completed(tx.objectStore(_storeName).put(json.toJS, _key.toJS));
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
