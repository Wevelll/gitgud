import 'dart:io';

import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:day_dial_store/day_dial_store.dart';

import 'repository_factory.dart';
import 'seed.dart';

/// Desktop/native: a persistent SQLite store under the user's home directory,
/// plus a localhost data-API server so the web companion can sync to it.
Future<DayRepository> openPlatformRepository() async {
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

  // Serve the web companion on localhost. Best-effort: if the port is taken,
  // the desktop app still runs fully; only browser sync is unavailable.
  try {
    // The server stays alive via its own accept loop for the process lifetime.
    final server = DataApiServer(DayDialTools(repo, const AllowAllConsent()));
    final uri = await server.start(port: 7788);
    stderr.writeln('Day-Dial hub serving the web companion at $uri');
  } catch (e) {
    stderr.writeln('Day-Dial hub not started (web sync unavailable): $e');
  }

  return repo;
}
