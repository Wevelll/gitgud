import 'package:day_dial/notifications/notification_scheduler.dart';
import 'package:day_dial/notifications/notifier.dart';
import 'package:day_dial_core/day_dial_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class _FakeNotifier implements Notifier {
  final List<({String title, String body})> sent = [];
  @override
  Future<void> notify({required String title, required String body}) async {
    sent.add((title: title, body: body));
  }
}

void main() {
  NotificationScheduler scheduler({int lead = 0}) => NotificationScheduler(
    repo: InMemoryDayRepository(profiles: [testProfile()]),
    notifier: _FakeNotifier(),
    leadMinutes: lead,
    clock: () => DateTime(2026, 7, 3, 7, 30), // 07:30, inside Morning
  );

  test('nextAlert points at the next block transition', () {
    final s = scheduler();
    final alert = s.nextAlert(450)!;
    // testProfile: Morning 07:00–09:00, so Deep work is next at 09:00.
    expect(alert.block.name, 'Deep work');
    expect(alert.minutesUntil, 90);
    expect(alert.message, 'Deep work starts now');
    s.dispose();
  });

  test('lead time changes the message and the fire time', () {
    final s = scheduler(lead: 10);
    final alert = s.nextAlert(450)!;
    expect(alert.minutesUntil, 80);
    expect(alert.message, 'Deep work starts in 10 min');
    s.dispose();
  });
}
