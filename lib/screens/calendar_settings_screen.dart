import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../calendar/calendar_service.dart';
import '../painters/dial_painter.dart' show parseHexColor;

/// Manage read-only calendar subscriptions (SPEC §12.1): add / remove / toggle
/// ICS or CalDAV URLs whose events overlay the dial. A refresh re-pulls them.
///
/// Note: sources live for the session only — durable persistence goes through
/// the store layer (SPEC §5 `calendar_sources`) and is a pending follow-up.
class CalendarSettingsScreen extends StatefulWidget {
  const CalendarSettingsScreen({
    super.key,
    required this.service,
    this.onChanged,
  });

  final CalendarService service;

  /// Called after any change that alters the overlay (add/remove/toggle/refresh).
  final VoidCallback? onChanged;

  @override
  State<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends State<CalendarSettingsScreen> {
  static const _panel = Color(0xFF0E1322);
  bool _busy = false;

  CalendarService get _service => widget.service;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final failed = await _service.refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged?.call();
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not fetch: ${failed.join(', ')}')),
      );
    }
  }

  /// Persists the (mutated) source list, then re-pulls events.
  Future<void> _persistAndRefresh() async {
    await _service.persist();
    await _refresh();
  }

  Future<void> _addDialog() async {
    final result = await showDialog<CalendarSource>(
      context: context,
      builder: (_) => const _AddSourceDialog(),
    );
    if (result == null) return;
    _service.addSource(result);
    setState(() {});
    await _persistAndRefresh();
  }

  void _toggle(CalendarSource s, bool enabled) {
    _service.replaceSource(s.copyWith(enabled: enabled));
    setState(() {});
    _persistAndRefresh();
  }

  void _remove(CalendarSource s) {
    _service.removeSource(s.id);
    setState(() {});
    _persistAndRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final sources = _service.sources;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Calendars'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add calendar'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Read-only overlay. Paste an ICS subscription or CalDAV URL '
                  '(webcal:// works too). Events show on the dial, never as '
                  'blocks.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 16),
                if (sources.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'No calendars yet — add one with the button below.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  )
                else
                  for (final s in sources) _sourceRow(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceRow(CalendarSource s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: parseHexColor(s.colorHex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${s.kind.name.toUpperCase()} · ${s.url ?? s.calId ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: s.enabled, onChanged: (v) => _toggle(s, v)),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: () => _remove(s),
            icon: const Icon(Icons.delete_outline, size: 20),
            color: const Color(0xFFB5624F),
          ),
        ],
      ),
    );
  }
}

/// Collects a new calendar source: name, URL, kind, and a color.
class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  CalendarSourceKind _kind = CalendarSourceKind.ics;
  String _color = '#7C7CA8';
  String? _error;

  static const _colors = [
    '#7C7CA8',
    '#3E7CB1',
    '#6FA85B',
    '#C98A3E',
    '#B5624F',
    '#8E6FB0',
  ];

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) {
      setState(() => _error = 'Name and URL are required');
      return;
    }
    Navigator.pop(
      context,
      CalendarSource(
        id: 'cal-${DateTime.now().microsecondsSinceEpoch}',
        kind: _kind,
        name: name,
        url: url,
        colorHex: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add calendar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'ICS / CalDAV URL',
                hintText: 'https://… or webcal://…',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CalendarSourceKind>(
              segments: const [
                ButtonSegment(
                  value: CalendarSourceKind.ics,
                  label: Text('ICS'),
                ),
                ButtonSegment(
                  value: CalendarSourceKind.caldav,
                  label: Text('CalDAV'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final hex in _colors)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: parseHexColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hex == _color
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFB5624F))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
