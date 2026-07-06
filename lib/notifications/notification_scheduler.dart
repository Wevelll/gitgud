import 'dart:async';

import 'package:day_dial_core/day_dial_core.dart';

import 'notifier.dart';

/// Fires a [Notifier] at each day-block transition. It reads the schedule from
/// the active profile via `core` ([transitionAlerts]) and sleeps until the next
/// one; call [reschedule] after the day changes (a block edit or profile
/// switch) and [dispose] to stop.
///
/// The UI is a thin client: all the "when/what" is core logic; this only owns a
/// [Timer] and the platform [notifier].
class NotificationScheduler {
  NotificationScheduler({
    required this.repo,
    required this.notifier,
    this.leadMinutes = 0,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DayRepository repo;
  final Notifier notifier;

  /// Fire this many minutes before each block starts (0 = at the transition).
  final int leadMinutes;

  final DateTime Function() _clock;
  Timer? _timer;

  int _nowMin() {
    final n = _clock();
    return n.hour * 60 + n.minute;
  }

  /// The next alert from [nowMin], or null if the active profile has no upcoming
  /// transition. Pure (no timer) so it can be unit-tested directly.
  TransitionAlert? nextAlert(int nowMin) {
    final alerts = transitionAlerts(
      repo.activeProfile(),
      fromMin: nowMin,
      count: 1,
      leadMinutes: leadMinutes,
    );
    return alerts.isEmpty ? null : alerts.first;
  }

  /// (Re)starts the schedule from the current time.
  void reschedule() {
    _timer?.cancel();
    final alert = nextAlert(_nowMin());
    if (alert == null) return;
    // Minute granularity is plenty for block transitions. A 0-minute result
    // means we're sitting on the boundary, so wait a minute and re-evaluate
    // (by then `upcomingFrom` reports the following block, avoiding a re-fire).
    final minutes = alert.minutesUntil <= 0 ? 1 : alert.minutesUntil;
    _timer = Timer(Duration(minutes: minutes), () {
      notifier.notify(title: alert.block.name, body: alert.message);
      reschedule();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
