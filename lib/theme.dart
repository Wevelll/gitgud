import 'package:flutter/material.dart';

/// The two Day-Dial themes. Rendering-only concern (golden rule #1): nothing
/// here touches core — screens read colors via [DayDialColors] so the same
/// widget code renders both modes.
///
/// Dark is the original look (deep navy, near-white ink). Light keeps the
/// segment palette and the dark dial hub as anchors so the product still
/// reads as Day-Dial, on paper-grey surfaces.
ThemeData dayDialDark() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF0A0D18),
    colorScheme: base.colorScheme.copyWith(
      surface: const Color(0xFF0A0D18),
      onSurface: Colors.white,
    ),
    // Bundled Roboto (see pubspec) — no CDN font fetch, works offline.
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
  );
}

ThemeData dayDialLight() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF2F3F8),
    colorScheme: base.colorScheme.copyWith(
      surface: const Color(0xFFF2F3F8),
      onSurface: const Color(0xFF1B2032),
      primary: const Color(0xFF4B4FA6),
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: const Color(0xFF1B2032),
      displayColor: const Color(0xFF1B2032),
    ),
  );
}

/// Theme-aware stand-ins for the colors the screens used to hardcode.
///
/// `ink` replaces `Colors.white` (text/icons), `panel` replaces the
/// `0xFF0E1322` card fill. In dark mode they resolve to exactly those old
/// values, so dark rendering is unchanged.
extension DayDialColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Primary text/icon color for the current theme.
  Color get ink => isDarkMode ? Colors.white : const Color(0xFF1B2032);

  /// [ink] at an opacity — secondary text, hairlines, faint fills.
  Color inkAlpha(double alpha) => ink.withValues(alpha: alpha);

  /// Card/panel background.
  Color get panel => isDarkMode ? const Color(0xFF0E1322) : Colors.white;
}
