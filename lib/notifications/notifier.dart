// Platform-split delivery: the browser Notifications API on web, a desktop
// seam (currently logging; Linux D-Bus / other OS delivery plugs in here)
// elsewhere. Mirrors the repository_factory / agent_host conditional-import
// idiom so day_dial's core stays platform-agnostic.
import 'notifier_io.dart' if (dart.library.js_interop) 'notifier_web.dart';

/// Delivers a single block-transition notification to the user. The scheduling
/// (when / what) is computed in `core`; this is only the platform's "show it".
abstract interface class Notifier {
  Future<void> notify({required String title, required String body});
}

/// The current platform's [Notifier].
Notifier createNotifier() => makeNotifier();
