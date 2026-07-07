import 'dart:io';

import 'exporter.dart';

/// Desktop/native exporter — writes the file into the user's Downloads folder
/// (falling back to the home dir, then the system temp dir) and returns its
/// path. A native save dialog (file_picker) is a later refinement.
Exporter makeExporter() => _IoExporter();

class _IoExporter implements Exporter {
  @override
  Future<String> save(String filename, String contents) async {
    final dir = Directory(_targetDir());
    if (!dir.existsSync()) await dir.create(recursive: true);
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }

  static String _targetDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      final downloads = Directory('$home/Downloads');
      if (downloads.existsSync()) return downloads.path;
      return home;
    }
    return Directory.systemTemp.path;
  }
}
