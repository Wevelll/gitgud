/// Host-side consent for mutating MCP tools (golden rules #4/#5, SPEC §6.2).
///
/// Every write flows through a [ConsentGate] before it touches state. Destructive
/// tools (e.g. `delete_block`) carry [ToolCall.destructive] so the host can warn
/// harder. No tool silently mutates — a denied gate raises [ConsentDeniedException].
library;

/// A pending mutating tool invocation, presented to the user for approval.
class ToolCall {
  const ToolCall({
    required this.tool,
    required this.arguments,
    this.destructive = false,
  });

  final String tool;
  final Map<String, Object?> arguments;

  /// Mirrors MCP's `destructiveHint`: this call removes or irreversibly changes
  /// data.
  final bool destructive;

  @override
  String toString() =>
      'ToolCall($tool${destructive ? ' [destructive]' : ''}, $arguments)';
}

/// Decides whether a mutating tool may proceed. Implemented by the host UI.
abstract interface class ConsentGate {
  Future<bool> requestConsent(ToolCall call);
}

/// Thrown when a mutating tool is invoked but consent is not granted.
class ConsentDeniedException implements Exception {
  const ConsentDeniedException(this.tool);
  final String tool;
  @override
  String toString() => 'ConsentDeniedException: user denied "$tool"';
}

/// Grants everything — for local dev and tests only. Never wire this into a
/// shipping host.
class AllowAllConsent implements ConsentGate {
  const AllowAllConsent();
  @override
  Future<bool> requestConsent(ToolCall call) async => true;
}

/// Denies everything — useful for verifying the gate blocks writes.
class DenyAllConsent implements ConsentGate {
  const DenyAllConsent();
  @override
  Future<bool> requestConsent(ToolCall call) async => false;
}

/// Delegates the decision to a callback and records what it was asked to
/// approve — the ergonomic gate for tests and simple hosts.
class CallbackConsent implements ConsentGate {
  CallbackConsent(this._decide);
  final Future<bool> Function(ToolCall call) _decide;

  final List<ToolCall> seen = [];

  @override
  Future<bool> requestConsent(ToolCall call) async {
    seen.add(call);
    return _decide(call);
  }
}
