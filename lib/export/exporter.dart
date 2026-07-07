// Platform-split file export (SPEC §12.3): writes to a file on desktop, triggers
// a browser download on web. Mirrors the notifier / repository_factory
// conditional-import idiom so `core` (which builds the export *content*) stays
// platform-agnostic — this seam only performs the platform's "save it".
import 'exporter_io.dart' if (dart.library.js_interop) 'exporter_web.dart';

/// Saves already-serialized export content (CSV / ICS / JSON produced by `core`).
abstract interface class Exporter {
  /// Persists [contents] under [filename]; returns a user-facing location (a
  /// file path on desktop, or "Downloads" on web).
  Future<String> save(String filename, String contents);
}

/// The current platform's [Exporter].
Exporter createExporter() => makeExporter();
