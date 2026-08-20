import 'dart:async';

import 'package:day_dial_core/day_dial_core.dart';

import 'mirrored_repository.dart';

/// Saves a whole snapshot to some backing store. Async because the browser's
/// IndexedDB is (the desktop's SQLite is not, and doesn't need this class).
typedef SnapshotSink = Future<void> Function(DaySnapshot snapshot);

/// A repository that mirrors every edit into an asynchronous store — the web
/// build's local persistence (SPEC §8: a real local store for the browser, so
/// the page is usable with no desktop hub reachable and survives a reload).
///
/// Writes are **coalesced, latest-wins**: while a save is in flight, further
/// edits mark the state dirty rather than queueing, and one more save runs when
/// the first finishes. A burst of edits (dragging a boundary) therefore costs
/// two writes, not fifty, and the store always converges on the newest state.
///
/// A failed save is swallowed on purpose: losing persistence must never take
/// the UI down with it. [lastError] exposes the most recent failure so a caller
/// can surface "changes aren't being saved" if it wants to.
class PersistedDayRepository extends MirroredDayRepository {
  PersistedDayRepository({
    required InMemoryDayRepository cache,
    required this.save,
  }) : super(cache);

  final SnapshotSink save;

  Future<void>? _draining;
  bool _dirty = false;
  Object? _lastError;

  /// The most recent save failure, if the last attempt failed; null once a
  /// save succeeds.
  Object? get lastError => _lastError;

  /// Completes when every pending edit has been written — what tests await,
  /// and what a "flush before close" would await.
  Future<void> get idle => _draining ?? Future<void>.value();

  @override
  void onMutated() {
    _dirty = true;
    _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_dirty) {
        _dirty = false;
        try {
          await save(cache.snapshot());
          _lastError = null;
        } catch (e) {
          _lastError = e;
        }
      }
    } finally {
      _draining = null;
    }
  }
}
