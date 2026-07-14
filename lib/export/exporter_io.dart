import 'dart:io';

import '../data/app_dirs_io.dart';
import 'exporter.dart';

/// Desktop/mobile exporter — writes the file into the platform's export
/// directory (Downloads on desktop, app documents on mobile) and returns its
/// path. A native save/share dialog (file_picker) is a later refinement.
Exporter makeExporter() => _IoExporter();

class _IoExporter implements Exporter {
  @override
  Future<String> save(String filename, String contents) async {
    final dir = await exportDirectory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }
}
