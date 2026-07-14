import 'dart:io';
import 'dart:math';

import 'package:day_dial_mcp/day_dial_mcp.dart';
import 'package:flutter/material.dart';

import 'activity_log.dart';
import 'agent_host.dart';

/// Desktop factory — a real loopback MCP server over the app repository.
/// Mobile is an MCP *client* of the desktop hub in v1 (SPEC §6.1) and hosts
/// no server, so it gets the same "unavailable" stub the web build uses.
AgentHost makeAgentHost({
  required DayRepository repository,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  if (Platform.isAndroid || Platform.isIOS) return _UnavailableAgentHost();
  return _IoAgentHost(repository, navigatorKey);
}

class _UnavailableAgentHost implements AgentHost {
  @override
  final ActivityLog activity = ActivityLog();

  @override
  bool get available => false;
  @override
  bool get running => false;
  @override
  Uri? get endpoint => null;
  @override
  String? get token => null;

  @override
  AgentConsentPolicy policy = AgentConsentPolicy.promptEveryWrite;

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

class _IoAgentHost implements AgentHost {
  _IoAgentHost(this._repo, GlobalKey<NavigatorState> navKey)
    : activity = ActivityLog(),
      _consent = _UiConsentGate(navKey);

  final DayRepository _repo;
  final _UiConsentGate _consent;

  @override
  final ActivityLog activity;

  McpHttpServer? _server;
  Uri? _endpoint;
  String? _token;

  @override
  bool get available => true;
  @override
  bool get running => _server != null;
  @override
  Uri? get endpoint => _endpoint;
  @override
  String? get token => _token;

  @override
  AgentConsentPolicy get policy => _consent.policy;
  @override
  set policy(AgentConsentPolicy value) => _consent.policy = value;

  @override
  Future<void> start() async {
    if (running) return;
    _token = _randomToken();
    final tools = _RecordingTools(_repo, _consent, activity);
    final http = McpHttpServer(McpServer(tools), token: _token);
    _endpoint = await http.start(); // binds 127.0.0.1 by default
    _server = http;
  }

  @override
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _endpoint = null;
    _token = null;
  }

  static String _randomToken() {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(24, (_) => hex[r.nextInt(16)]).join();
  }
}

/// Records each mutating tool call (and its outcome) to the activity feed.
/// Reads are not recorded — they would flood the feed with polling noise.
class _RecordingTools extends DayDialTools {
  _RecordingTools(super.repo, super.consent, this._log);
  final ActivityLog _log;

  static bool _isWrite(String tool) =>
      DayDialTools.specs.any((s) => s.name == tool && s.mutates);

  @override
  Future<Object?> call(
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    if (!_isWrite(tool)) return super.call(tool, args);
    try {
      final result = await super.call(tool, args);
      _record(tool, args, ActivityOutcome.allowed);
      return result;
    } on ConsentDeniedException {
      _record(tool, args, ActivityOutcome.denied);
      rethrow;
    } catch (_) {
      _record(tool, args, ActivityOutcome.error);
      rethrow;
    }
  }

  void _record(String tool, Map<String, Object?> args, ActivityOutcome o) {
    _log.add(
      ActivityEntry(
        tool: tool,
        summary: _summarize(tool, args),
        outcome: o,
        at: DateTime.now(),
      ),
    );
  }

  static String _summarize(String tool, Map<String, Object?> args) {
    final parts = args.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    return parts.isEmpty ? tool : '$tool($parts)';
  }
}

/// A [ConsentGate] that asks the user via a dialog, unless policy auto-approves
/// a non-destructive call. With no UI available it denies (the safe default).
class _UiConsentGate implements ConsentGate {
  _UiConsentGate(this._navKey);
  final GlobalKey<NavigatorState> _navKey;
  AgentConsentPolicy policy = AgentConsentPolicy.promptEveryWrite;

  @override
  Future<bool> requestConsent(ToolCall call) async {
    if (policy == AgentConsentPolicy.autoAllowSafe && !call.destructive) {
      return true;
    }
    final ctx = _navKey.currentContext;
    if (ctx == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(
          call.destructive
              ? 'Allow a destructive change?'
              : 'Allow agent change?',
        ),
        content: Text('An agent wants to run “${call.tool}”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
