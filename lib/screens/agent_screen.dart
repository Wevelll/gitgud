import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/activity_log.dart';
import '../agent/agent_host.dart';

/// The Agent panel: the app's own MCP server (SPEC §6) made visible — status,
/// how to connect, the consent policy, and a live feed of what agents changed.
class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key, required this.host});

  final AgentHost host;

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  static const _panel = Color(0xFF0E1322);
  AgentHost get _host => widget.host;

  Future<void> _toggleServer() async {
    if (_host.running) {
      await _host.stop();
    } else {
      await _host.start();
    }
    if (mounted) setState(() {});
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Agent'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_host.available)
                  _card(child: _unavailable())
                else ...[
                  _card(child: _serverControls()),
                  const SizedBox(height: 12),
                  _card(child: _consentControls()),
                  const SizedBox(height: 12),
                  _feedHeader(),
                  const SizedBox(height: 8),
                  _feed(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  Widget _unavailable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agent server runs on the desktop app',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'This device talks to your desktop hub instead of hosting its '
          'own MCP server. Run the Day-Dial desktop app to expose your day '
          'to agents.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
        ),
      ],
    );
  }

  Widget _serverControls() {
    final running = _host.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 12,
              color: running ? const Color(0xFF6FA85B) : Colors.white24,
            ),
            const SizedBox(width: 8),
            Text(
              running ? 'Server running' : 'Server stopped',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: _toggleServer,
              child: Text(running ? 'Stop' : 'Start'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Bound to 127.0.0.1 — pair a client with the token below.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        if (running) ...[
          const SizedBox(height: 12),
          _copyRow('Endpoint', _host.endpoint.toString()),
          const SizedBox(height: 8),
          _copyRow('Token', _host.token ?? ''),
        ],
      ],
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontFamily: 'monospace',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy $label',
          visualDensity: VisualDensity.compact,
          onPressed: () => _copy(label, value),
          icon: const Icon(Icons.copy, size: 18),
        ),
      ],
    );
  }

  Widget _consentControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHEN AN AGENT MAKES A CHANGE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<AgentConsentPolicy>(
          segments: const [
            ButtonSegment(
              value: AgentConsentPolicy.promptEveryWrite,
              label: Text('Ask me'),
            ),
            ButtonSegment(
              value: AgentConsentPolicy.autoAllowSafe,
              label: Text('Auto-allow safe'),
            ),
          ],
          selected: {_host.policy},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _host.policy = s.first),
        ),
        const SizedBox(height: 6),
        Text(
          'Deleting a block always asks, whatever the setting.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _feedHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'ACTIVITY',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        TextButton(
          onPressed: () => _host.activity.clear(),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _feed() {
    return AnimatedBuilder(
      animation: _host.activity,
      builder: (_, _) {
        final entries = _host.activity.entries;
        if (entries.isEmpty) {
          return _card(
            child: Text(
              'No agent activity yet. When a paired agent adds or changes '
              'something, it shows here.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          );
        }
        return Column(children: [for (final e in entries) _feedRow(e)]);
      },
    );
  }

  Widget _feedRow(ActivityEntry e) {
    final (color, label) = switch (e.outcome) {
      ActivityOutcome.allowed => (const Color(0xFF6FA85B), 'allowed'),
      ActivityOutcome.denied => (const Color(0xFFB5624F), 'denied'),
      ActivityOutcome.error => (const Color(0xFFC98A3E), 'error'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.summary,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
