import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter/material.dart';

import 'data/repository_factory.dart';
import 'screens/dial_screen.dart';

void main() => runApp(DayDialApp(repository: createRepository()));

class DayDialApp extends StatelessWidget {
  const DayDialApp({super.key, required this.repository});

  final DayRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Day-Dial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0D18),
        // Bundled Roboto (see pubspec) — no CDN font fetch, works offline.
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: DialScreen(repository: repository),
    );
  }
}
