import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import '../painters/dial_painter.dart' show parseHexColor;

/// Manages day templates (SPEC §2.4): create by block durations, assign
/// weekdays, set the default, rename, delete, or open one on the dial to edit
/// its blocks. Which template a date shows is resolved by weekday
/// ([DayRepository.profileForDate]); this screen authors them.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, required this.repository, this.onChanged});

  final DayRepository repository;

  /// Called after any change, so the host can reload the dial.
  final VoidCallback? onChanged;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  DayRepository get _repo => widget.repository;
  late List<DayProfile> _profiles = _repo.profiles();

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  void _changed() {
    setState(() => _profiles = _repo.profiles());
    widget.onChanged?.call();
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _toggleWeekday(DayProfile p, int isoWeekday) {
    final bit = 1 << (isoWeekday - 1);
    final mask = p.activeDaysMask ^ bit;
    _repo.setProfileWeekdays(p.id, mask);
    _changed();
  }

  void _delete(String id) {
    try {
      _repo.removeProfile(id);
      _changed();
    } on StateError catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _rename(DayProfile p) async {
    final name = await _promptText('Rename template', p.name);
    if (name == null || name.isEmpty) return;
    _repo.setProfileName(p.id, name);
    _changed();
  }

  Future<String?> _promptText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editOnDial(String id) {
    _repo.switchProfile(id);
    widget.onChanged?.call();
    Navigator.pop(context);
  }

  Future<void> _newTemplate() async {
    final r = await showDialog<_TemplateData>(
      context: context,
      builder: (_) => const _TemplateDialog(),
    );
    if (r == null) return;
    final id =
        'tmpl-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    try {
      _repo.addProfile(
        DayProfile.fromDurations(id: id, name: r.name, blocks: r.blocks),
      );
      _changed();
    } on InvalidProfileException catch (e) {
      _showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTemplate,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [for (final p in _profiles) _card(p)],
      ),
    );
  }

  Widget _card(DayProfile p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: p.isDefault ? 'Default template' : 'Make default',
                  onPressed: p.isDefault
                      ? null
                      : () {
                          _repo.setDefaultProfile(p.id);
                          _changed();
                        },
                  icon: Icon(p.isDefault ? Icons.star : Icons.star_border),
                ),
                IconButton(
                  tooltip: 'Rename',
                  onPressed: () => _rename(p),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _delete(p.id),
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFFB5624F),
                ),
              ],
            ),
            // Ring preview: block names + durations.
            Text(
              [
                for (final s in p.segments)
                  '${s.name} ${formatDuration(s.durationMin)}',
              ].join(' · '),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'DAYS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(width: 8),
                for (var d = 1; d <= 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _weekdayDot(p, d),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => _editOnDial(p.id),
                  child: const Text('Edit blocks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayDot(DayProfile p, int isoWeekday) {
    final on = p.appliesToWeekday(isoWeekday);
    return InkWell(
      onTap: () => _toggleWeekday(p, isoWeekday),
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 13,
        backgroundColor: on
            ? const Color(0xFF3E7CB1)
            : Colors.white.withValues(alpha: 0.08),
        child: Text(
          _dayLabels[isoWeekday - 1],
          style: TextStyle(
            fontSize: 11,
            color: on ? Colors.white : Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// The result of the new-template dialog.
class _TemplateData {
  const _TemplateData(this.name, this.blocks);
  final String name;
  final List<({String name, String colorHex, int minutes})> blocks;
}

const _kPalette = [
  '#4B4FA6',
  '#3E7CB1',
  '#6FA85B',
  '#C98A3E',
  '#2E8B8B',
  '#B5624F',
  '#8E6FB0',
  '#5A9FB0',
];

/// One editable block row (a name + whole hours).
class _BlockRow {
  _BlockRow(String name, int hours, this.colorHex)
    : name = TextEditingController(text: name),
      hours = TextEditingController(text: '$hours');
  final TextEditingController name;
  final TextEditingController hours;
  final String colorHex;
}

/// Create a template by block durations — the "how many hours on Sleep / Work /
/// Free" flow, generalised to any blocks. Must total 24 hours.
class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog();

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  final _name = TextEditingController(text: 'Weekend');
  final _rows = [
    _BlockRow('Sleep', 8, '#4B4FA6'),
    _BlockRow('Work', 8, '#3E7CB1'),
    _BlockRow('Free', 8, '#6FA85B'),
  ];
  String? _error;

  int get _totalHours =>
      _rows.fold(0, (s, r) => s + (int.tryParse(r.hours.text.trim()) ?? 0));

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.hours.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(
      () => _rows.add(_BlockRow('Block', 0, _kPalette[_rows.length % 8])),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (_totalHours != 24) {
      setState(() => _error = 'Blocks must total 24 h (now $_totalHours h)');
      return;
    }
    final blocks = <({String name, String colorHex, int minutes})>[];
    for (final r in _rows) {
      final h = int.tryParse(r.hours.text.trim()) ?? 0;
      if (h <= 0) {
        setState(() => _error = 'Each block needs at least 1 h');
        return;
      }
      blocks.add((
        name: r.name.text.trim().isEmpty ? 'Block' : r.name.text.trim(),
        colorHex: r.colorHex,
        minutes: h * 60,
      ));
    }
    Navigator.pop(context, _TemplateData(name, blocks));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New template'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            for (final r in _rows) _row(r),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add block'),
              ),
            ),
            Text(
              'Total: $_totalHours h / 24 h',
              style: TextStyle(
                color: _totalHours == 24
                    ? const Color(0xFF6FA85B)
                    : const Color(0xFFB5624F),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
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
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Widget _row(_BlockRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: parseHexColor(r.colorHex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: r.name,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: TextField(
              controller: r.hours,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, suffixText: 'h'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _rows.length <= 2
                ? null
                : () => setState(() => _rows.remove(r)),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
          ),
        ],
      ),
    );
  }
}
