import 'package:day_dial_core/day_dial_core.dart';

import 'repository_factory.dart';
import 'seed.dart';
import 'synced_day_repository.dart';

/// Web: sync with the desktop hub (SPEC §8). The hub URL/token can be passed as
/// query params (`?hub=http://127.0.0.1:7788&token=…`); the default assumes the
/// desktop app is running locally.
///
/// If the hub is unreachable, fall back to a non-persistent in-memory store so
/// the page still works (view / light-edit), matching the spec's IndexedDB
/// fallback intent until that lands.
Future<DayRepository> openPlatformRepository() async {
  final params = Uri.base.queryParameters;
  final hub = Uri.parse(params['hub'] ?? 'http://127.0.0.1:7788');
  final token = params['token'];
  try {
    return await SyncedDayRepository.connect(hub: hub, token: token);
  } catch (_) {
    final repo = InMemoryDayRepository(profiles: [defaultProfile()]);
    seedTasksIfEmpty(repo);
    return repo;
  }
}
