import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import 'agent/agent_host.dart';
import 'data/repository_factory.dart';
import 'screens/dial_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await createRepository();
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

  @override
  void dispose() {
    _agent.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Day-Dial',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0D18),
        // Bundled Roboto (see pubspec) — no CDN font fetch, works offline.
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: DialScreen(repository: widget.repository, agentHost: _agent),
    );
  }
}
