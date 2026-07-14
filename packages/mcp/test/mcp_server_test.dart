import 'dart:convert';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:test/test.dart';

DayProfile weekday() => DayProfile.ring(
  id: 'weekday',
  name: 'Weekday',
  isDefault: true,
  segmentIds: const ['sleep', 'morning', 'work'],
  spans: const [
    (startMin: 1380, name: 'Sleep', colorHex: '#4B4FA6'),
    (startMin: 420, name: 'Morning', colorHex: '#C98A3E'),
    (startMin: 540, name: 'Work', colorHex: '#3E7CB1'),
  ],
);

DateTime fixedClock() => DateTime(2026, 7, 3, 7, 30);

McpServer server({ConsentGate consent = const AllowAllConsent()}) {
  final repo = InMemoryDayRepository(profiles: [weekday()], clock: fixedClock);
  return McpServer(DayDialTools(repo, consent, clock: fixedClock));
}

Map<String, Object?> req(
  Object? id,
  String method, [
  Map<String, Object?>? params,
]) => {
  'jsonrpc': '2.0',
  if (id != null) 'id': id,
  'method': method,
  if (params != null) 'params': params,
};

void main() {
  test('initialize echoes protocol version and advertises tools', () async {
    final r = await server().handle(
      req(1, 'initialize', {'protocolVersion': '2025-06-18'}),
    );
    final result = r!['result'] as Map;
    expect(result['protocolVersion'], '2025-06-18');
    expect((result['capabilities'] as Map)['tools'], isNotNull);
    expect((result['serverInfo'] as Map)['name'], 'day-dial');
  });

  test('notifications get no response', () async {
    final r = await server().handle(req(null, 'notifications/initialized'));
    expect(r, isNull);
  });

  test(
    'tools/list returns all tools with schemas and destructive hints',
    () async {
      final r = await server().handle(req(2, 'tools/list'));
      final tools = ((r!['result'] as Map)['tools'] as List)
          .cast<Map<String, Object?>>();
      expect(tools.length, DayDialTools.specs.length);
      for (final t in tools) {
        expect(t['inputSchema'], isA<Map<String, Object?>>());
      }
      final del = tools.firstWhere((t) => t['name'] == 'delete_block');
      expect((del['annotations'] as Map)['destructiveHint'], isTrue);
    },
  );

  test('tools/call runs a read tool and returns structured content', () async {
    final r = await server().handle(
      req(3, 'tools/call', {'name': 'get_current_block'}),
    );
    final result = r!['result'] as Map;
    expect(result['isError'], isFalse);
    final structured = (result['structuredContent'] as Map)['result'] as Map;
    expect(structured['name'], 'Morning');
    // The text content mirrors the structured result as JSON.
    final text = ((result['content'] as List).first as Map)['text'] as String;
    expect((jsonDecode(text) as Map)['name'], 'Morning');
  });

  test(
    'denied consent surfaces as an isError tool result, not a crash',
    () async {
      final r = await server(consent: const DenyAllConsent()).handle(
        req(4, 'tools/call', {
          'name': 'add_block',
          'arguments': {'name': 'Gym', 'start': '10:00', 'end': '11:00'},
        }),
      );
      final result = r!['result'] as Map;
      expect(result['isError'], isTrue);
      final text = ((result['content'] as List).first as Map)['text'] as String;
      expect(text, contains('denied'));
    },
  );

  test('domain errors become isError results', () async {
    final r = await server().handle(
      req(5, 'tools/call', {
        'name': 'delete_block',
        'arguments': {'id': 'nope'},
      }),
    );
    expect((r!['result'] as Map)['isError'], isTrue);
  });

  test('unknown method is a JSON-RPC error', () async {
    final r = await server().handle(req(6, 'bogus/method'));
    expect((r!['error'] as Map)['code'], -32601);
  });
}
