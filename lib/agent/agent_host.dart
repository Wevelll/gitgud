import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/widgets.dart';

import 'activity_log.dart';
// Desktop hosts a real MCP server; web can't (no dart:io), so it reports
// unavailable. Conditional import keeps day_dial_mcp/dart:io out of the web build.
import 'agent_host_io.dart' if (dart.library.js_interop) 'agent_host_web.dart';

/// How agent writes are approved (golden rule #4: writes always go through a
/// consent layer — "auto-allow safe" is a standing consent, destructive still
/// prompts).
enum AgentConsentPolicy {
  /// Prompt the user for every mutating tool call.
  promptEveryWrite,

  /// Auto-approve non-destructive edits this session; still prompt for
  /// destructive ones (e.g. delete_block).
  autoAllowSafe,
}

/// The app's optional embedded MCP server, exposed to the Agent panel. The
/// concrete host is platform-specific (see the conditional import).
abstract class AgentHost {
  /// Live feed of agent tool calls.
  ActivityLog get activity;

  /// False on web (no server can run there).
  bool get available;

  bool get running;

  /// The bound endpoint once [start] has run (always loopback).
  Uri? get endpoint;

  /// The pairing token a client must present.
  String? get token;

  AgentConsentPolicy get policy;
  set policy(AgentConsentPolicy value);

  /// Starts the loopback MCP server. No-op on web.
  Future<void> start();

  /// Stops the server.
  Future<void> stop();
}

/// Creates the platform's [AgentHost] over the app [repository]. [navigatorKey]
/// lets the consent gate raise dialogs from the server's request handler.
AgentHost createAgentHost({
  required DayRepository repository,
  required GlobalKey<NavigatorState> navigatorKey,
}) => makeAgentHost(repository: repository, navigatorKey: navigatorKey);
