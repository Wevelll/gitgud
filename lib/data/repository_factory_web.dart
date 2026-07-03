import 'package:day_dial_core/day_dial_core.dart';

import 'repository_factory.dart';
import 'seed.dart';

/// Web: a non-persistent in-memory store (view / light-edit). A real IndexedDB
/// store is a later slice; this keeps the web build free of dart:ffi/dart:io.
DayRepository openPlatformRepository() {
  final repo = InMemoryDayRepository(profiles: [defaultProfile()]);
  seedTasksIfEmpty(repo);
  return repo;
}
