import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import 'agent/agent_host.dart';
import 'calendar/calendar_service.dart';
import 'calendar/source_store.dart';
import 'data/prefs_store.dart';
import 'data/repository_factory.dart';
import 'notifications/notification_scheduler.dart';
import 'notifications/notifier.dart';
import 'screens/dial_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await createRepository();
  // Show today's template (its weekday assignment, else the default).
  final today = CivilDate.fromDateTime(DateTime.now());
  repository.switchProfile(repository.profileForDate(today).id);
  runApp(DayDialApp(repository: repository));
}

class DayDialApp extends StatefulWidget {
  const DayDialApp({super.key, required this.repository});

  final DayRepository repository;

  @override
  State<DayDialApp> createState() => _DayDialAppState();
}

class _DayDialAppState extends State<DayDialApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AgentHost _agent = createAgentHost(
    repository: widget.repository,
    navigatorKey: _navigatorKey,
  );

  // Fires a native notification at each block transition (SPEC §11 MVP).
  late final NotificationScheduler _scheduler = NotificationScheduler(
    repo: widget.repository,
    notifier: createNotifier(),
  );

  // Read-only calendar overlay (SPEC §12.1). Subscriptions persist via the
  // platform source store (a JSON file on desktop; session-only on web); the
  // dial loads and refreshes them on start. Manage them from the Calendars
  // screen.
  final CalendarService _calendar = CalendarService(
    store: createCalendarSourceStore(),
  );

  // Theme preference: follows the OS by default, cycleable from the dial
  // toolbar, persisted as a device-local pref (never synced user data).
  final PrefsStore _prefs = createPrefsStore();
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _scheduler.reschedule();
    _prefs.read('theme_mode').then((v) {
      final mode = switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (mode != _themeMode && mounted) setState(() => _themeMode = mode);
    });
  }

  void _cycleTheme() {
    final next = switch (_themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setState(() => _themeMode = next);
    _prefs.write('theme_mode', next.name);
  }

  @override
  void dispose() {
    _scheduler.dispose();
    _agent.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Day-Dial',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: dayDialLight(),
      darkTheme: dayDialDark(),
      themeMode: _themeMode,
      home: DialScreen(
        repository: widget.repository,
        agentHost: _agent,
        calendarService: _calendar,
        onDayChanged: _scheduler.reschedule,
        themeMode: _themeMode,
        onCycleTheme: _cycleTheme,
      ),
    );
  }
}
