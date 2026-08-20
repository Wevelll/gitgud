import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

/// User preferences on the repository: opaque string key/values that survive a
/// snapshot round-trip, so a choice made on one device (or in a browser tab)
/// isn't lost the next time the day is loaded.
void main() {
  DayProfile profile() => DayProfile.fromDurations(
        id: 'p',
        name: 'Day',
        isDefault: true,
        segmentIds: const ['a', 'b'],
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Awake', colorHex: '#6FA85B', minutes: 960),
        ],
      );

  InMemoryDayRepository repo() => InMemoryDayRepository(profiles: [profile()]);

  test('a fresh repository has no settings', () {
    expect(repo().settings(), isEmpty);
    expect(repo().getSetting('dial.mode'), isNull);
  });

  test('set then read, and setting again replaces', () {
    final r = repo();
    r.setSetting('dial.mode', 'clock');
    expect(r.getSetting('dial.mode'), 'clock');

    r.setSetting('dial.mode', 'compass');
    expect(r.getSetting('dial.mode'), 'compass');
    expect(r.settings(), {'dial.mode': 'compass'});
  });

  test('settings() is a read-only view', () {
    final r = repo()..setSetting('dial.mode', 'clock');
    expect(() => r.settings()['x'] = 'y', throwsUnsupportedError);
  });

  test('settings survive a snapshot round-trip', () {
    final r = repo()
      ..setSetting('dial.mode', 'clock')
      ..setSetting('anything.else', '42');

    final json = r.snapshot().toJson();
    final restored = InMemoryDayRepository.fromSnapshot(
      DaySnapshot.fromJson(json),
    );

    expect(restored.getSetting('dial.mode'), 'clock');
    expect(restored.getSetting('anything.else'), '42');
  });

  test('restore replaces the settings wholesale', () {
    final source = repo()..setSetting('dial.mode', 'clock');
    final target = repo()..setSetting('stale.key', 'gone');

    target.restore(source.snapshot());

    expect(target.getSetting('dial.mode'), 'clock');
    expect(target.getSetting('stale.key'), isNull);
  });

  test('a snapshot written before settings existed still loads', () {
    final json = repo().snapshot().toJson()..remove('settings');
    expect(DaySnapshot.fromJson(json).settings, isEmpty);
  });
}
