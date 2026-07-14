import 'dart:convert';

import '../consent.dart';
import '../tools.dart';

/// The MCP protocol version this server advertises. Echoes the client's
/// requested version when compatible; this is the fallback.
const String kProtocolVersion = '2025-06-18';

/// A transport-agnostic MCP server: pure request → response over JSON-RPC 2.0,
/// no I/O. The stdio and HTTP transports feed it decoded maps and ship whatever
/// it returns; that keeps all protocol logic unit-testable without sockets.
///
/// Handles `initialize`, `ping`, `tools/list`, and `tools/call` over
/// [DayDialTools]. Tool *execution* errors (bad args, denied consent) come back
/// as `isError` tool results per the MCP spec; only malformed/unknown *requests*
/// become JSON-RPC error objects.
class McpServer {
  McpServer(this.tools, {this.name = 'day-dial', this.version = '0.0.1'});

  final DayDialTools tools;
  final String name;
  final String version;

  /// Handles one decoded JSON-RPC message. Returns the response map, or `null`
  /// for notifications (no `id`), which get no reply.
  Future<Map<String, Object?>?> handle(Map<String, Object?> request) async {
    final id = request['id'];
    final method = request['method'];
    final isNotification = !request.containsKey('id');

    if (method is! String) {
      return isNotification
          ? null
          : _error(id, -32600, 'Invalid Request: missing method');
    }

    // Notifications (e.g. notifications/initialized) are acknowledged silently.
    if (isNotification) {
      return null;
    }

    final params = (request['params'] as Map?)?.cast<String, Object?>() ?? {};

    try {
      switch (method) {
        case 'initialize':
          return _result(id, _initialize(params));
        case 'ping':
          return _result(id, {});
        case 'tools/list':
          return _result(id, {'tools': _toolList()});
        case 'tools/call':
          return _result(id, await _callTool(params));
        default:
          return _error(id, -32601, 'Method not found: $method');
      }
    } catch (e) {
      // Unexpected server-side failure (not a tool error, which is handled
      // inside _callTool) — report as an internal JSON-RPC error.
      return _error(id, -32603, 'Internal error: $e');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final requested = params['protocolVersion'];
    return {
      'protocolVersion': requested is String ? requested : kProtocolVersion,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': name, 'version': version},
    };
  }

  List<Map<String, Object?>> _toolList() => [
    for (final s in DayDialTools.specs)
      {
        'name': s.name,
        'description': s.description,
        'inputSchema': s.inputSchema,
        if (s.destructive) 'annotations': {'destructiveHint': true},
      },
  ];

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final toolName = params['name'];
    if (toolName is! String) {
      return _toolError('tools/call requires a string "name"');
    }
    final args =
        (params['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
    try {
      final result = await tools.call(toolName, args);
      return {
        'content': [
          {'type': 'text', 'text': jsonEncode(result)},
        ],
        'structuredContent': {'result': result},
        'isError': false,
      };
    } on ConsentDeniedException catch (e) {
      return _toolError(e.toString());
    } on ArgumentError catch (e) {
      return _toolError('${e.message}');
    } on FormatException catch (e) {
      return _toolError('Invalid argument: ${e.message}');
    } catch (e) {
      // Domain errors (e.g. InvalidProfileException, StateError) are surfaced
      // to the caller as tool errors, not protocol crashes.
      return _toolError(e.toString());
    }
  }

  Map<String, Object?> _toolError(String message) => {
    'content': [
      {'type': 'text', 'text': message},
    ],
    'isError': true,
  };

  Map<String, Object?> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
