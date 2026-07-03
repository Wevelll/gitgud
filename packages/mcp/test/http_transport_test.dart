import 'dart:convert';
import 'dart:io';

import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:test/test.dart';

McpServer buildServer() {
  final repo = InMemoryDayRepository(
    profiles: [defaultWeekdayProfile()],
    clock: () => DateTime(2026, 7, 3, 7, 30),
  );
  return McpServer(DayDialTools(repo, const AllowAllConsent(),
      clock: () => DateTime(2026, 7, 3, 7, 30)));
}

/// POSTs [payload] to [uri], returning (status, decoded-json-or-null).
Future<(int, Object?)> post(
  Uri uri,
  Object payload, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (body.isEmpty) return (res.statusCode, null);
    // Reject responses are plain text; success responses are JSON.
    try {
      return (res.statusCode, jsonDecode(body));
    } on FormatException {
      return (res.statusCode, body);
    }
  } finally {
    client.close();
  }
}

Map<String, Object?> rpc(int id, String method,
        [Map<String, Object?>? params]) =>
    {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params
    };

void main() {
  group('Streamable HTTP transport', () {
    late McpHttpServer server;
    late Uri uri;

    tearDown(() async => server.close());

    test('binds loopback and answers initialize', () async {
      server = McpHttpServer(buildServer());
      uri = await server.start();
      expect(uri.host, '127.0.0.1'); // never 0.0.0.0

      final (status, body) = await post(uri, rpc(1, 'initialize'));
      expect(status, 200);
      expect(((body! as Map)['result'] as Map)['serverInfo'], isNotNull);
    });

    test('runs a tools/call over HTTP', () async {
      server = McpHttpServer(buildServer());
      uri = await server.start();

      final (status, body) =
          await post(uri, rpc(2, 'tools/call', {'name': 'get_current_block'}));
      expect(status, 200);
      final result = ((body! as Map)['result'] as Map);
      final structured = (result['structuredContent'] as Map)['result'] as Map;
      expect(structured['name'], 'Morning');
    });

    test('rejects a non-local Origin (DNS-rebinding guard)', () async {
      server = McpHttpServer(buildServer());
      uri = await server.start();

      final (status, _) = await post(uri, rpc(3, 'initialize'),
          headers: {'origin': 'http://evil.example.com'});
      expect(status, HttpStatus.forbidden);
    });

    test('allows a localhost Origin', () async {
      server = McpHttpServer(buildServer());
      uri = await server.start();

      final (status, _) = await post(uri, rpc(4, 'ping'),
          headers: {'origin': 'http://localhost:5173'});
      expect(status, 200);
    });

    test('token gate: missing/wrong is 401, correct passes', () async {
      server = McpHttpServer(buildServer(), token: 'sekret');
      uri = await server.start();

      final (noTok, _) = await post(uri, rpc(5, 'ping'));
      expect(noTok, HttpStatus.unauthorized);

      final (badTok, _) = await post(uri, rpc(6, 'ping'),
          headers: {'authorization': 'Bearer nope'});
      expect(badTok, HttpStatus.unauthorized);

      final (goodTok, body) = await post(uri, rpc(7, 'ping'),
          headers: {'authorization': 'Bearer sekret'});
      expect(goodTok, 200);
      expect((body! as Map)['result'], isNotNull);
    });

    test('accepts the token via query parameter too', () async {
      server = McpHttpServer(buildServer(), token: 'sekret');
      uri = await server.start();

      final (status, _) = await post(
          uri.replace(queryParameters: {'token': 'sekret'}), rpc(8, 'ping'));
      expect(status, 200);
    });

    test('a notification gets 202 and no body', () async {
      server = McpHttpServer(buildServer());
      uri = await server.start();

      final (status, body) = await post(
          uri, {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
      expect(status, HttpStatus.accepted);
      expect(body, isNull);
    });
  });
}
