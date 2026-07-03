import 'dart:convert';
import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:test/test.dart';

DayProfile weekday() => DayProfile.ring(
      id: 'weekday',
      name: 'Weekday',
      isDefault: true,
      segmentIds: const ['sleep', 'work'],
      spans: const [
        (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
        (startMin: 420, name: 'Work', colorHex: '#3E7CB1'),
      ],
    );

DataApiServer buildServer({String? token}) {
  final repo = InMemoryDayRepository(profiles: [weekday()]);
  return DataApiServer(DayDialTools(repo, const AllowAllConsent()),
      token: token);
}

Future<(int, Object?)> req(
  Uri uri, {
  String method = 'GET',
  Object? body,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final r = await client.openUrl(method, uri);
    headers.forEach(r.headers.set);
    if (body != null) {
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body));
    }
    final res = await r.close();
    final text = await utf8.decodeStream(res);
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = text;
    }
    return (res.statusCode, decoded);
  } finally {
    client.close();
  }
}

void main() {
  late DataApiServer server;
  late Uri base;
  tearDown(() => server.close());

  test('GET /state returns a hydratable snapshot', () async {
    server = buildServer();
    base = await server.start();
    expect(base.host, '127.0.0.1');

    final (status, body) = await req(base.replace(path: '/state'));
    expect(status, 200);
    final json = ((body! as Map)['state'] as Map).cast<String, Object?>();
    final snap = DaySnapshot.fromJson(json);
    final repo = InMemoryDayRepository.fromSnapshot(snap);
    expect(repo.activeProfile().name, 'Weekday');
  });

  test('POST /call runs a mutating tool; /state reflects it', () async {
    server = buildServer();
    base = await server.start();

    final (status, body) = await req(
      base.replace(path: '/call'),
      method: 'POST',
      body: {
        'name': 'add_habit',
        'arguments': {'label': 'Water', 'target': 8}
      },
    );
    expect(status, 200);
    expect(((body! as Map)['result'] as Map)['label'], 'Water');

    // The mutation is visible in a fresh snapshot.
    final (_, state) = await req(base.replace(path: '/state'));
    final snap = DaySnapshot.fromJson(
        ((state! as Map)['state'] as Map).cast<String, Object?>());
    expect(snap.habits.single.label, 'Water');
  });

  test('a failing tool returns an error, not a crash', () async {
    server = buildServer();
    base = await server.start();
    final (status, body) = await req(
      base.replace(path: '/call'),
      method: 'POST',
      body: {
        'name': 'log_habit',
        'arguments': {'id': 'nonexistent'}
      },
    );
    expect(status, HttpStatus.badRequest);
    expect((body! as Map)['error'], isNotNull);
  });

  test('non-local Origin is blocked; token gates when set', () async {
    server = buildServer(token: 'sekret');
    base = await server.start();

    final (forbidden, _) = await req(base.replace(path: '/state'),
        headers: {'origin': 'http://evil.example.com'});
    expect(forbidden, HttpStatus.forbidden);

    final (unauth, _) = await req(base.replace(path: '/state'));
    expect(unauth, HttpStatus.unauthorized);

    final (ok, _) = await req(base.replace(path: '/state'),
        headers: {'authorization': 'Bearer sekret'});
    expect(ok, 200);
  });
}
