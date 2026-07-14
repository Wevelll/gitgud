import 'dart:convert';
import 'dart:io';

import '../protocol/mcp_server.dart';

/// Serves an [McpServer] over stdio using newline-delimited JSON-RPC — the
/// zero-config, same-machine transport (SPEC §6.1) that Claude Desktop/Code use.
///
/// Contract: **stdout carries only JSON-RPC messages** (one compact JSON object
/// per line). All logging must go to stderr, or it will corrupt the stream.
/// Completes when stdin closes.
Future<void> serveStdio(
  McpServer server, {
  Stream<List<int>>? input,
  IOSink? output,
}) async {
  final out = output ?? stdout;
  final lines = (input ?? stdin)
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Map<String, Object?> request;
    try {
      request = (jsonDecode(trimmed) as Map).cast<String, Object?>();
    } catch (_) {
      out.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32700, 'message': 'Parse error'},
        }),
      );
      continue;
    }

    final response = await server.handle(request);
    if (response != null) {
      out.writeln(jsonEncode(response));
    }
  }
}
