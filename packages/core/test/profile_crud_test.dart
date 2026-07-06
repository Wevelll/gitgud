import 'package:day_dial_core/day_dial_core.dart';
import 'package:test/test.dart';

void main() {
  DayProfile weekday() => DayProfile.fromDurations(
        id: 'weekday',
        name: 'Weekday',
        isDefault: true,
        activeDaysMask: 31, // Mon–Fri
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Work', colorHex: '#3E7CB1', minutes: 480),
          (name: 'Free', colorHex: '#6FA85B', minutes: 480),
        ],
      );

  DayProfile weekend({int mask = 0}) => DayProfile.fromDurations(
        id: 'weekend',
        name: 'Weekend',
        activeDaysMask: mask,
        blocks: const [
          (name: 'Sleep', colorHex: '#4B4FA6', minutes: 480),
          (name: 'Free', colorHex: '#6FA85B', minutes: 960),
        ],
      );

  InMemoryDayRepository repo() => InMemoryDayRepository(profiles: [weekday()]);

  final monday = CivilDate.parse('2026-07-06');
  final saturday = CivilDate.parse('2026-07-11');

  test('addProfile + profileForDate resolves by weekday', () {
    final r = repo()..addProfile(weekend(mask: 96)); // Sat–Sun
    expect(r.profileForDate(monday).id, 'weekday');
    expect(r.profileForDate(saturday).id, 'weekend');
  });

  test('addProfile rejects a duplicate id', () {
    expect(() => repo().addProfile(weekday()), throwsStateError);
  });

  test('setProfileWeekdays changes which day resolves to it', () {
    final r = repo()..addProfile(weekend());
    r.setProfileWeekdays('weekend', 96);
    expect(r.profileForDate(saturday).id, 'weekend');
  });

  test('setDefaultProfile moves the default flag to exactly one', () {
    final r = repo()..addProfile(weekend());
    r.setDefaultProfile('weekend');
    expect(r.profiles().firstWhere((p) => p.id == 'weekend').isDefault, isTrue);
    expect(
        r.profiles().firstWhere((p) => p.id == 'weekday').isDefault, isFalse);
  });

  test('setProfileName renames', () {
    final r = repo()..setProfileName('weekday', 'Workday');
    expect(r.activeProfile().name, 'Workday');
  });

  test('removeProfile guards the active and last profiles', () {
    final r = repo()..addProfile(weekend(mask: 96));
    expect(() => r.removeProfile('weekday'), throwsStateError); // active
    r.removeProfile('weekend');
    expect(r.profiles().map((p) => p.id), ['weekday']);
    expect(() => r.removeProfile('weekday'), throwsStateError); // last
  });

  test('removeProfile purges the profile\'s sub-blocks', () {
    final r = repo()..addProfile(weekend(mask: 96));
    r.switchProfile('weekend');
    r.addSubBlock(
      parentId: 'weekend.seg1', // Free 08:00–24:00
      name: 'Gym',
      colorHex: '#abc',
      startMin: 480,
      endMin: 540,
    );
    expect(r.subBlocks().of('weekend.seg1'), isNotEmpty);

    r.switchProfile('weekday'); // so weekend isn't the active profile
    r.removeProfile('weekend');
    expect(r.subBlocks().of('weekend.seg1'), isEmpty);
  });
}
