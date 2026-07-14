import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:day_dial_core/day_dial_core.dart';

import '../tools.dart';

/// A small HTTP data API for the **web companion** (SPEC §8): the desktop hub
/// exposes its state so a browser client can render live and mirror edits back,
/// while SQLite on the desktop stays the single source of truth.
///
/// Endpoints:
/// - `GET  /state` → the full [DaySnapshot] as JSON (one round-trip hydrates the
///   web client).
/// - `POST /call`  → `{ "name": <tool>, "arguments": {...} }`, dispatched
///   through [DayDialTools] (the same tool layer agents use); returns
///   `{ "result": ... }` or `{ "error": ... }`.
///
/// Same security posture as the MCP HTTP transport (golden rule #5): binds
/// `127.0.0.1` by default, validates the `Origin` header, and token-gates when a
/// token is set.
class DataApiServer {
  DataApiServer(this.tools, {this.token});

  final DayDialTools tools;
  final String? token;

  HttpServer? _http;
  Uri? _endpoint;
  Uri? get endpoint => _endpoint;

  Future<Uri> start({int port = 0, InternetAddress? address}) async {
    final addr = address ?? InternetAddress.loopbackIPv4;
    final http = await HttpServer.bind(addr, port);
    _http = http;
    _endpoint = Uri(scheme: 'http', host: addr.address, port: http.port);
    _accept(http);
    return _endpoint!;
  }

  Future<void> close() async {
    await _http?.close(force: true);
    _http = null;
  }

  Future<void> _accept(HttpServer http) async {
    await for (final req in http) {
      unawaited(_dispatch(req));
    }
  }

  Future<void> _dispatch(HttpRequest req) async {
    final res = req.response;
    res.headers.set('access-control-allow-origin', _corsOrigin(req));
    res.headers.set(
      'access-control-allow-headers',
      'authorization,content-type',
    );
    res.headers.set('access-control-allow-methods', 'GET,POST,PUT,OPTIONS');
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        return res.close();
      }
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

      if (req.method == 'GET' && req.uri.path == '/state') {
        return _json(res, {'state': tools.repo.snapshot().toJson()});
      }
      if (req.method == 'PUT' && req.uri.path == '/state') {
        return _handleRestore(req);
      }
      if (req.method == 'POST' && req.uri.path == '/call') {
        return _handleCall(req);
      }
      return _reject(req, HttpStatus.notFound, 'Not found');
    } catch (e) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        res.write(jsonEncode({'error': '$e'}));
      } finally {
        await res.close();
      }
    }
  }

  Future<void> _handleRestore(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    try {
      final json = (jsonDecode(body) as Map).cast<String, Object?>();
      final state = (json['state'] as Map).cast<String, Object?>();
      tools.repo.restore(DaySnapshot.fromJson(state));
      return _json(req.response, {'ok': true});
    } catch (e) {
      return _json(req.response, {
        'error': '$e',
      }, status: HttpStatus.badRequest);
    }
  }

  Future<void> _handleCall(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    Map<String, Object?> payload;
    try {
      payload = (jsonDecode(body) as Map).cast<String, Object?>();
    } catch (_) {
      return _json(req.response, {
        'error': 'Malformed JSON',
      }, status: HttpStatus.badRequest);
    }
    final name = payload['name'];
    if (name is! String) {
      return _json(req.response, {
        'error': 'Missing tool "name"',
      }, status: HttpStatus.badRequest);
    }
    final args =
        (payload['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
    try {
      final result = await tools.call(name, args);
      return _json(req.response, {'result': result});
    } catch (e) {
      return _json(req.response, {
        'error': '$e',
      }, status: HttpStatus.badRequest);
    }
  }

  Future<void> _json(
    HttpResponse res,
    Map<String, Object?> body, {
    int status = HttpStatus.ok,
  }) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    return res.close();
  }

  Future<void> _reject(HttpRequest req, int status, String message) async {
    await req.drain<void>();
    req.response.statusCode = status;
    req.response.write(message);
    await req.response.close();
  }

  String _corsOrigin(HttpRequest req) {
    final o = req.headers.value('origin');
    return (o != null && _isLocalOrigin(o)) ? o : 'null';
  }

  bool _isLocalOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    const localHosts = {'localhost', '127.0.0.1', '::1'};
    return localHosts.contains(uri.host);
  }

  bool _authorized(HttpRequest req) {
    if (req.headers.value('authorization') == 'Bearer $token') return true;
    if (req.uri.queryParameters['token'] == token) return true;
    return false;
  }
}
