import 'package:flutter/foundation.dart';

/// What happened to an agent tool call.
enum ActivityOutcome { allowed, denied, error }

/// One entry in the agent activity feed.
class ActivityEntry {
  ActivityEntry({
    required this.tool,
    required this.summary,
    required this.outcome,
    required this.at,
  });

  final String tool;
  final String summary;
  final ActivityOutcome outcome;
  final DateTime at;
}

/// A bounded, newest-first log of what agents have done — the data behind the
/// Agent panel's feed. Web-safe (foundation only).
class ActivityLog extends ChangeNotifier {
  ActivityLog({this.maxEntries = 200});
  final int maxEntries;

  final List<ActivityEntry> _entries = [];

  /// Newest first.
  List<ActivityEntry> get entries => List.unmodifiable(_entries.reversed);

  void add(ActivityEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
