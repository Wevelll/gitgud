import 'dart:convert';
import 'dart:io';

import 'package:day_dial/agent/activity_log.dart';
import 'package:day_dial/agent/agent_host.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<(int, Map<String, Object?>?)> rpc(
  Uri uri,
  String token,
  String method,
  Map<String, Object?> params,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.headers.set('authorization', 'Bearer $token');
    req.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      }),
    );
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (body.isEmpty) return (res.statusCode, null);
    try {
      return (
        res.statusCode,
        (jsonDecode(body) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return (res.statusCode, null);
    }
  } finally {
    client.close();
  }
}

AgentHost hostFor(DayRepository repo) => createAgentHost(
  repository: repo,
  navigatorKey: GlobalKey<NavigatorState>(),
);

// These use real sockets, so they run as plain `test` (no Flutter binding,
// which would mock HttpClient). The consent-denial path is covered at the mcp
// layer (DenyAllConsent → isError); here we prove the host wiring: loopback
// bind, token gate, tool dispatch, and the activity feed.
void main() {
  test('auto-allow-safe permits a write over HTTP and records it', () async {
    final repo = testRepository();
    final host = hostFor(repo)..policy = AgentConsentPolicy.autoAllowSafe;
    await host.start();
    expect(host.running, isTrue);
    expect(host.endpoint!.host, '127.0.0.1');
    final before = repo.activeProfile().segments.length;

    final (status, resp) = await rpc(
      host.endpoint!,
      host.token!,
      'tools/call',
      {
        'name': 'add_block',
        'arguments': {'name': 'Gym', 'start': '10:00', 'end': '11:00'},
      },
    );

    expect(status, 200);
    expect((resp!['result'] as Map)['isError'], isFalse);
    expect(repo.activeProfile().segments.any((s) => s.name == 'Gym'), isTrue);
    expect(repo.activeProfile().segments.length, greaterThan(before));
    expect(host.activity.entries, hasLength(1));
    expect(host.activity.entries.first.outcome, ActivityOutcome.allowed);
    await host.stop();
  });

  test('reads do not require consent and are not recorded', () async {
    final repo = testRepository();
    final host = hostFor(repo);
    await host.start();

    final (status, resp) = await rpc(
      host.endpoint!,
      host.token!,
      'tools/call',
      {'name': 'get_current_block'},
    );

    expect(status, 200);
    expect((resp!['result'] as Map)['isError'], isFalse);
    expect(host.activity.entries, isEmpty); // reads stay out of the feed
    await host.stop();
  });

  test('an unpaired client is rejected by the token gate', () async {
    final repo = testRepository();
    final host = hostFor(repo);
    await host.start();
    final (status, _) = await rpc(host.endpoint!, 'wrong', 'ping', const {});
    expect(status, HttpStatus.unauthorized);
    await host.stop();
  });
}
