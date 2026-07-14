import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifier.dart';

/// Native notifier over flutter_local_notifications: Android, iOS, macOS,
/// Linux (D-Bus) and Windows (toasts). Web has its own browser-API notifier
/// (notifier_web.dart), so this file never enters the web build.
///
/// Delivery is strictly local (golden rule #6): no push service, no network.
/// If the platform offers no notification service (headless test runs,
/// stripped-down desktops, denied permission), it degrades to a debug log so
/// the scheduling path still works end to end.
Notifier makeNotifier() => LocalNotifier();

class LocalNotifier implements Notifier {
  LocalNotifier() {
    // Initialize (and raise the OS permission prompt where one applies) at
    // app start rather than at the first transition, which may be hours away.
    _ready = _init();
  }

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  late final Future<bool> _ready;

  Future<bool> _init() async {
    // The Linux implementation talks to the notification service over the
    // session D-Bus. Without a session bus (headless runs, bare containers)
    // its connection error surfaces *asynchronously* — outside the try/catch
    // below — as an unhandled zone error, so check for the bus up front.
    if (Platform.isLinux && !_linuxHasSessionBus()) {
      debugPrint('[Day-Dial] notifications unavailable: no session D-Bus');
      return false;
    }
    try {
      const darwin = DarwinInitializationSettings(
        requestBadgePermission: false,
      );
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'Day-Dial',
            appUserModelId: 'io.github.wevelll.day_dial',
            // Identifies Day-Dial's toast activation to Windows. Any GUID
            // works as long as it stays fixed — changing it orphans toasts.
            guid: 'a2d8f4c1-6b3e-4f7a-9c5d-8e1b0a2f6d43',
          ),
        ),
      );
      if (Platform.isAndroid) {
        // Android 13+ gates notifications behind a runtime permission.
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      return ok ?? true;
    } catch (e) {
      debugPrint('[Day-Dial] notifications unavailable: $e');
      return false;
    }
  }

  static bool _linuxHasSessionBus() {
    final env = Platform.environment;
    if (env['DBUS_SESSION_BUS_ADDRESS'] != null) return true;
    final runtimeDir = env['XDG_RUNTIME_DIR'];
    return runtimeDir != null && File('$runtimeDir/bus').existsSync();
  }

  @override
  Future<void> notify({required String title, required String body}) async {
    if (!await _ready) {
      debugPrint('[Day-Dial] $title — $body');
      return;
    }
    try {
      await _plugin.show(
        // One fixed slot: a new transition replaces the previous banner
        // instead of piling up a day's worth of stale alerts.
        id: 0,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'transitions',
            'Segment transitions',
            channelDescription:
                'Alerts when the current segment of your day changes',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Day-Dial] $title — $body ($e)');
    }
  }
}
