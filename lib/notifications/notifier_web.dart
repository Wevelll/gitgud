import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'notifier.dart';

/// Web notifier using the browser Notifications API — no plugin needed. Asks
/// for permission the first time and, once granted, shows a native notification.
Notifier makeNotifier() => WebNotifier();

class WebNotifier implements Notifier {
  @override
  Future<void> notify({required String title, required String body}) async {
    var permission = web.Notification.permission;
    if (permission == 'default') {
      permission = (await web.Notification.requestPermission().toDart).toDart;
    }
    if (permission == 'granted') {
      web.Notification(title, web.NotificationOptions(body: body));
    }
  }
}
