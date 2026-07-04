import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/widgets.dart';

import 'activity_log.dart';
import 'agent_host.dart';

/// Web factory — no server (no dart:io), so the panel shows it as unavailable.
AgentHost makeAgentHost({
  required DayRepository repository,
  required GlobalKey<NavigatorState> navigatorKey,
}) => _WebAgentHost();

class _WebAgentHost implements AgentHost {
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
