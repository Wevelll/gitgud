import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'exporter.dart';

/// Web exporter — builds a Blob and clicks a hidden download link, so the file
/// lands in the browser's Downloads with no plugin (uses the same `package:web`
/// bindings as the web notifier). Nothing leaves the device.
Exporter makeExporter() => _WebExporter();

class _WebExporter implements Exporter {
  @override
  Future<String> save(String filename, String contents) async {
    final parts = <JSAny>[contents.toJS].toJS;
    final blob = web.Blob(
      parts,
      web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return 'Downloads';
  }
}
