import 'dart:io';

import 'package:day_dial_mcp/day_dial_mcp.dart';

/// Dev harness for the Day-Dial MCP server.
///
/// Runs the tool layer over an in-memory store so you can point Claude
/// Desktop/Code at it today:
///
///   dart run day_dial_mcp             # stdio (default; zero-config)
///   dart run day_dial_mcp --http      # Streamable HTTP on 127.0.0.1
///   dart run day_dial_mcp --http --port 7337 --token secret
///
/// NOTE: this harness uses [AllowAllConsent] because a bare CLI process has no
/// UI to prompt on. In the shipping product the desktop app **embeds** this
/// server and injects its own interactive [ConsentGate] (golden rule #4) — the
/// consent seam is already in place; only the gate implementation differs.
Future<void> main(List<String> args) async {
  final useHttp = args.contains('--http');
  final port = _intFlag(args, '--port') ?? 0;
  final token = _stringFlag(args, '--token');

  final repo = InMemoryDayRepository(profiles: [defaultWeekdayProfile()]);
  final server = McpServer(DayDialTools(repo, const AllowAllConsent()));

  if (useHttp) {
    final http = McpHttpServer(server, token: token);
    final uri = await http.start(port: port);
    stderr.writeln('Day-Dial MCP (Streamable HTTP) listening at $uri');
    if (token == null) {
      stderr.writeln('WARNING: no --token set; bound to 127.0.0.1 only.');
    }
    // Keep running until the process is killed.
    await ProcessSignal.sigint.watch().first;
    await http.close();
  } else {
    stderr.writeln('Day-Dial MCP (stdio) ready.');
    await serveStdio(server);
  }
}

int? _intFlag(List<String> args, String name) {
  final v = _stringFlag(args, name);
  return v == null ? null : int.tryParse(v);
}

String? _stringFlag(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}
