import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_store/day_dial_store.dart';

import 'repository_factory.dart';
import 'seed.dart';

/// Desktop/native: a persistent SQLite store under the user's home directory.
DayRepository openPlatformRepository() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  final dir = Directory('$home/.day_dial')..createSync(recursive: true);
  final repo = SqliteDayRepository.open(
    path: '${dir.path}/day.db',
    seedIfEmpty: [defaultProfile()],
  );
  seedTasksIfEmpty(repo);
  return repo;
}
