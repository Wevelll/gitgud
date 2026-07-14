import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/mcp_server.dart';

/// Serves an [McpServer] over Streamable HTTP (SPEC §6.1) for LAN / other-agent
/// access.
///
/// Security posture is load-bearing (golden rule #5):
/// - **Binds `127.0.0.1` by default.** LAN exposure is opt-in via [start]'s
///   `address` — never defaults to `0.0.0.0`.
/// - **Validates the `Origin` header** so a malicious web page can't drive the
///   server via DNS rebinding; only localhost origins (or no Origin) pass.
/// - **Token-gated** when a [token] is set: requests must present it via
///   `Authorization: Bearer <token>` or a `?token=` query parameter.
///
/// This is a minimal request/response Streamable HTTP endpoint: it accepts POSTs
/// of a single JSON-RPC message or a batch array and replies with JSON. (SSE
/// streaming can be layered on later; the protocol allows a plain-JSON server.)
class McpHttpServer {
  McpHttpServer(this._server, {this.token, this.path = '/mcp'});

  final McpServer _server;

  /// Pairing token; when non-null, every request must present it.
  final String? token;

  /// The single endpoint path this server answers on.
  final String path;

  HttpServer? _http;

  /// The bound URI once [start] has run.
  Uri? get endpoint => _endpoint;
  Uri? _endpoint;

  /// Binds and begins serving. Defaults to `127.0.0.1`; pass a LAN [address]
  /// only when the user has explicitly opted in. Returns the endpoint URI.
  Future<Uri> start({int port = 0, InternetAddress? address}) async {
    final addr = address ?? InternetAddress.loopbackIPv4;
    final http = await HttpServer.bind(addr, port);
    _http = http;
    _endpoint = Uri(
      scheme: 'http',
      host: addr.address,
      port: http.port,
      path: path,
    );
    _accept(http);
    return _endpoint!;
  }

  Future<void> close() async {
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _accept(HttpServer http) async {
    await for (final request in http) {
      // Handle each request independently; never let one failure kill the loop.
      unawaited(_dispatch(request));
    }
  }

  Future<void> _dispatch(HttpRequest req) async {
    final res = req.response;
    try {
      final origin = req.headers.value('origin');
      if (origin != null && !_isLocalOrigin(origin)) {
        return _reject(req, HttpStatus.forbidden, 'Cross-origin blocked');
      }
      if (token != null && !_authorized(req)) {
        return _reject(
          req,
          HttpStatus.unauthorized,
          'Invalid or missing token',
        );
      }
      if (req.method != 'POST' || req.uri.path != path) {
        return _reject(req, HttpStatus.notFound, 'Not found');
      }

      final body = await utf8.decodeStream(req);
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        res.statusCode = HttpStatus.badRequest;
        res.headers.contentType = ContentType.json;
        res.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32700, 'message': 'Parse error'},
          }),
        );
        return res.close();
      }

      // Single message or JSON-RPC batch.
      if (decoded is List) {
        final responses = <Map<String, Object?>>[];
        for (final item in decoded) {
          final r = await _handleOne(item);
          if (r != null) responses.add(r);
        }
        if (responses.isEmpty) {
          res.statusCode = HttpStatus.accepted;
          return res.close();
        }
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(responses));
        return res.close();
      }

      final response = await _handleOne(decoded);
      if (response == null) {
        res.statusCode = HttpStatus.accepted; // notification, no body
        return res.close();
      }
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(response));
      return res.close();
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        res.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32603, 'message': 'Internal error: $e'},
          }),
        );
      } finally {
        await res.close();
      }
    }
  }

  Future<Map<String, Object?>?> _handleOne(Object? message) {
    if (message is! Map) {
      return Future.value({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32600, 'message': 'Invalid Request'},
      });
    }
    return _server.handle(message.cast<String, Object?>());
  }

  bool _isLocalOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    const localHosts = {'localhost', '127.0.0.1', '::1'};
    return localHosts.contains(uri.host);
  }

  bool _authorized(HttpRequest req) {
    final header = req.headers.value('authorization');
    if (header == 'Bearer $token') return true;
    if (req.uri.queryParameters['token'] == token) return true;
    return false;
  }

  Future<void> _reject(HttpRequest req, int status, String message) async {
    // Drain any request body first; responding over an undrained request can
    // reset the connection before the client reads the status.
    await req.drain<void>();
    final res = req.response;
    res.statusCode = status;
    res.write(message);
    await res.close();
  }
}
