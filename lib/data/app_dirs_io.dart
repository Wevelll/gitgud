import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where Day-Dial keeps its durable local data (`day.db`, calendar sources).
///
/// Android/iOS sandbox the filesystem — `$HOME` is not a writable app dir
/// there — so mobile resolves through path_provider's app-support directory
/// (durable and app-private; never the cache dir, which the OS may purge).
/// Desktop keeps the plain dot-directory under the user's home: no plugin
/// channel involved, so headless runs and the pure-Dart tests work unchanged.
Future<Directory> appDataDirectory() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return getApplicationSupportDirectory();
  }
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return Directory('$home/.day_dial');
}

/// Where exports land: the user's Downloads folder where one exists (desktop),
/// the app documents directory on mobile (visible via the OS Files app on
/// iOS; shareable from there), falling back to home, then the temp dir.
Future<Directory> exportDirectory() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return getApplicationDocumentsDirectory();
  }
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null) {
    final downloads = Directory('$home/Downloads');
    return downloads.existsSync() ? downloads : Directory(home);
  }
  return Directory.systemTemp;
}
