import 'package:flutter/material.dart';

import 'screens/dial_screen.dart';

void main() => runApp(const DayDialApp());

class DayDialApp extends StatelessWidget {
  const DayDialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Day-Dial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0D18)),
      home: const DialScreen(),
    );
  }
}
