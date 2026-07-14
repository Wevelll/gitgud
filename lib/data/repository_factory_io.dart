import 'dart:io';

import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:day_dial_store/day_dial_store.dart';

import 'app_dirs_io.dart';
import 'repository_factory.dart';
import 'seed.dart';

/// Desktop/mobile: a persistent SQLite store in the platform's app-data
/// directory; on desktop additionally a localhost data-API server so the web
/// companion can sync to it.
Future<DayRepository> openPlatformRepository() async {
  final dir = await appDataDirectory();
  dir.createSync(recursive: true);
  final repo = SqliteDayRepository.open(
    path: '${dir.path}/day.db',
    seedIfEmpty: [defaultProfile()],
  );
  seedTasksIfEmpty(repo);

  // Only the desktop app is the hub (SPEC §6.1); mobile is a client-only
  // store in v1 and hosts no servers.
  final isDesktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  if (isDesktop) {
    // Serve the web companion on localhost. Best-effort: if the port is taken,
    // the desktop app still runs fully; only browser sync is unavailable.
    try {
      // The server stays alive via its own accept loop for the process
      // lifetime.
      final server = DataApiServer(DayDialTools(repo, const AllowAllConsent()));
      final uri = await server.start(port: 7788);
      stderr.writeln('Day-Dial hub serving the web companion at $uri');
    } catch (e) {
      stderr.writeln('Day-Dial hub not started (web sync unavailable): $e');
    }
  }

  return repo;
}
