import 'package:day_dial_core/day_dial_core.dart';

import 'browser_store.dart';
import 'persisted_day_repository.dart';
import 'repository_factory.dart';
import 'seed.dart';
import 'synced_day_repository.dart';

/// How long to wait for the desktop hub before giving up and going local. Short
/// on purpose: the common case is "no hub running", and the user should get a
/// working page immediately, not a blank one while a socket times out.
const _hubTimeout = Duration(seconds: 3);

/// Web: sync with the desktop hub if one is reachable (SPEC §8), else keep the
/// day locally in IndexedDB.
///
/// The hub URL/token can be passed as query params
/// (`?hub=http://127.0.0.1:7788&token=…`); the default assumes the desktop app
/// is running on this machine. Pass `?local=1` to skip the hub entirely and
/// always use browser-local storage.
///
/// The local store is real persistence, not a scratch buffer: close the tab,
/// come back, and the day is still there. Only if IndexedDB itself is
/// unavailable (private-browsing modes, some embedded webviews) does the page
/// fall back to a session-lifetime in-memory store.
Future<DayRepository> openPlatformRepository() async {
  final params = Uri.base.queryParameters;
  if (params['local'] != '1') {
    final hub = Uri.parse(params['hub'] ?? 'http://127.0.0.1:7788');
    try {
      return await SyncedDayRepository.connect(
        hub: hub,
        token: params['token'],
      ).timeout(_hubTimeout);
    } catch (_) {
      // No hub — fall through to local storage.
    }
  }
  return openLocalRepository();
}

/// The browser-local repository: a snapshot in IndexedDB, rewritten after every
/// edit.
Future<DayRepository> openLocalRepository() async {
  try {
    final store = await BrowserSnapshotStore.open();
    final saved = await store.read();
    final repo = PersistedDayRepository(
      cache: _cacheFor(saved),
      save: store.write,
    );
    // Only a genuinely fresh store gets the demo tasks/habits — re-seeding a
    // restored one would resurrect anything the user deleted.
    if (saved == null) seedTasksIfEmpty(repo);
    return repo;
  } catch (_) {
    final repo = InMemoryDayRepository(profiles: [defaultProfile()]);
    seedTasksIfEmpty(repo);
    return repo;
  }
}

/// Rebuilds the in-memory state from [saved], or starts a fresh day.
///
/// Both paths get a restart-safe [uniqueIdFactory]: the default `id1, id2, …`
/// counter would start over on every page load and hand out ids that the
/// restored snapshot already uses.
InMemoryDayRepository _cacheFor(DaySnapshot? saved) => saved == null
    ? InMemoryDayRepository(
        profiles: [defaultProfile()],
        idFactory: uniqueIdFactory(),
      )
    : InMemoryDayRepository.fromSnapshot(saved, idFactory: uniqueIdFactory());
