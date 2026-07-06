import 'package:flutter/foundation.dart';

import 'notifier.dart';

/// Desktop/native notifier. Real OS delivery (Linux libnotify / D-Bus, and the
/// mobile plugins later) plugs in here; for now it logs, so the whole
/// scheduling path is exercised end-to-end without an unverifiable dependency.
Notifier makeNotifier() => const DebugNotifier();

class DebugNotifier implements Notifier {
  const DebugNotifier();

  @override
  Future<void> notify({required String title, required String body}) async {
    debugPrint('[Day-Dial] $title — $body');
  }
}
