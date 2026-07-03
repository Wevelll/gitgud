/// Time-of-day helpers.
///
/// Golden rule (CLAUDE.md #7): time-of-day is **minutes since midnight** as an
/// `int` in `[0, 1440)`. Never a `DateTime`, never seconds. Everything on the
/// dial that talks about "when in the day" flows through here.
library;

/// Minutes in one day.
const int minutesPerDay = 1440;

/// Minimum length of a segment, in minutes (SPEC §2.4).
const int minSegmentMinutes = 15;

/// Positive modulo — Dart's `%` already returns non-negative for positive
/// divisors, but we wrap it for intent and to guard negative deltas.
int mod(int n, int m) => ((n % m) + m) % m;

/// Normalizes any minute value into the canonical `[0, 1440)` range.
int normalizeMinute(int minute) => mod(minute, minutesPerDay);

/// Forward distance from [start] to [end] going clockwise (the direction time
/// flows on the dial), always in `[0, 1440)`. This is the primitive that makes
/// midnight-wrap "just work": `spanMinutes(1380, 420)` (23:00 → 07:00) is 480.
int spanMinutes(int start, int end) => mod(end - start, minutesPerDay);

/// Parses `"HH:MM"` into minutes since midnight. Also accepts a bare integer
/// string (already minutes). Throws [FormatException] on garbage or
/// out-of-range values, so MCP tool inputs fail loudly rather than silently
/// wrapping.
int parseMinuteOfDay(String input) {
  final trimmed = input.trim();
  if (!trimmed.contains(':')) {
    final asInt = int.tryParse(trimmed);
    if (asInt == null) {
      throw FormatException('Not a time or minute value', input);
    }
    if (asInt < 0 || asInt >= minutesPerDay) {
      throw FormatException('Minute out of range [0,1440)', input);
    }
    return asInt;
  }
  final parts = trimmed.split(':');
  if (parts.length != 2) {
    throw FormatException('Expected HH:MM', input);
  }
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) {
    throw FormatException('Non-numeric HH:MM', input);
  }
  if (h < 0 || h > 23 || m < 0 || m > 59) {
    throw FormatException('HH must be 0-23 and MM 0-59', input);
  }
  return h * 60 + m;
}

/// Formats minutes since midnight as `"HH:MM"`. Accepts out-of-range input and
/// normalizes it first, matching the prototype's `fmt`.
String formatMinuteOfDay(int minute) {
  final m = normalizeMinute(minute);
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Formats a duration in minutes as `"1h 30m"` / `"45m"` / `"2h"`, matching the
/// prototype's `fmtDur`.
String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
