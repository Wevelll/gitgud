import 'dart:convert';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:http/http.dart' as http;

/// The web companion's repository: a thin client over the desktop hub's data
/// API (SPEC §8).
///
/// It keeps an in-memory cache so the existing (synchronous) UI works unchanged,
/// and after every edit pushes the whole snapshot back to the hub via
/// `PUT /state` — the desktop persists it to SQLite, which stays the source of
/// truth. This is a **single-writer** model (good enough for one browser talking
/// to one desktop); concurrent-edit merging is the parked CRDT work.
class SyncedDayRepository implements DayRepository {
  SyncedDayRepository({
    required DaySnapshot initial,
    required this.hub,
    this.token,
    http.Client? client,
  }) : _cache = InMemoryDayRepository.fromSnapshot(initial),
       _client = client ?? http.Client();

  final InMemoryDayRepository _cache;
  final Uri hub;
  final String? token;
  final http.Client _client;

  /// Fetches the current snapshot from the hub to build a client.
  static Future<SyncedDayRepository> connect({
    required Uri hub,
    String? token,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    final res = await c.get(hub.replace(path: '/state'), headers: _auth(token));
    if (res.statusCode != 200) {
      throw StateError('Hub /state returned ${res.statusCode}');
    }
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final state = (json['state'] as Map).cast<String, Object?>();
    return SyncedDayRepository(
      initial: DaySnapshot.fromJson(state),
      hub: hub,
      token: token,
      client: c,
    );
  }

  static Map<String, String> _auth(String? token) =>
      token == null ? const {} : {'authorization': 'Bearer $token'};

  /// Pushes the current cache state to the hub. Best-effort: a failed push
  /// (hub offline) leaves the local cache intact so the UI keeps working.
  void _push() {
    final body = jsonEncode({'state': _cache.snapshot().toJson()});
    _client
        .put(
          hub.replace(path: '/state'),
          headers: {..._auth(token), 'content-type': 'application/json'},
          body: body,
        )
        .ignore();
  }

  // ---- reads (from cache) ---------------------------------------------------

  @override
  DayProfile activeProfile() => _cache.activeProfile();
  @override
  List<DayProfile> profiles() => _cache.profiles();
  @override
  DayProfile profileForDate(CivilDate date) => _cache.profileForDate(date);
  @override
  List<RecurringTask> tasks() => _cache.tasks();
  @override
  List<TaskCompletion> completions() => _cache.completions();
  @override
  List<TimeLog> logs() => _cache.logs();
  @override
  List<Habit> habits() => _cache.habits();
  @override
  List<HabitEvent> habitEvents() => _cache.habitEvents();
  @override
  SubBlockPlan subBlocks() => _cache.subBlocks();
  @override
  DaySnapshot snapshot() => _cache.snapshot();

  // ---- writes (cache first, then push) --------------------------------------

  @override
  void switchProfile(String profileId) {
    _cache.switchProfile(profileId);
    _push();
  }

  @override
  void addProfile(DayProfile profile) {
    _cache.addProfile(profile);
    _push();
  }

  @override
  void removeProfile(String id) {
    _cache.removeProfile(id);
    _push();
  }

  @override
  void setProfileName(String id, String name) {
    _cache.setProfileName(id, name);
    _push();
  }

  @override
  void setProfileWeekdays(String id, int activeDaysMask) {
    _cache.setProfileWeekdays(id, activeDaysMask);
    _push();
  }

  @override
  void setDefaultProfile(String id) {
    _cache.setDefaultProfile(id);
    _push();
  }

  @override
  Segment addBlock({
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final s = _cache.addBlock(
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _push();
    return s;
  }

  @override
  Segment updateBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    final s = _cache.updateBlock(
      id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _push();
    return s;
  }

  @override
  void deleteBlock(String id) {
    _cache.deleteBlock(id);
    _push();
  }

  @override
  Segment addSubBlock({
    required String parentId,
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final s = _cache.addSubBlock(
      parentId: parentId,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _push();
    return s;
  }

  @override
  Segment updateSubBlock(
    String id, {
    String? name,
    String? colorHex,
    int? startMin,
    int? endMin,
  }) {
    final s = _cache.updateSubBlock(
      id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    _push();
    return s;
  }

  @override
  void deleteSubBlock(String id) {
    _cache.deleteSubBlock(id);
    _push();
  }

  @override
  RecurringTask addRecurringTask({
    required String label,
    required Recurrence recurrence,
    required String colorHex,
  }) {
    final t = _cache.addRecurringTask(
      label: label,
      recurrence: recurrence,
      colorHex: colorHex,
    );
    _push();
    return t;
  }

  @override
  RecurringTask updateRecurringTask(
    String id, {
    String? label,
    String? colorHex,
    Recurrence? recurrence,
  }) {
    final t = _cache.updateRecurringTask(
      id,
      label: label,
      colorHex: colorHex,
      recurrence: recurrence,
    );
    _push();
    return t;
  }

  @override
  void setTaskArchived(String id, {required bool archived}) {
    _cache.setTaskArchived(id, archived: archived);
    _push();
  }

  @override
  void deleteRecurringTask(String id) {
    _cache.deleteRecurringTask(id);
    _push();
  }

  @override
  void completeTask(String taskId, CivilDate date) {
    _cache.completeTask(taskId, date);
    _push();
  }

  @override
  void uncompleteTask(String taskId, CivilDate date) {
    _cache.uncompleteTask(taskId, date);
    _push();
  }

  @override
  TimeLog logActual({
    required String category,
    required String startTs,
    required String endTs,
    String? segmentId,
    String? note,
    LogSource source = LogSource.manual,
  }) {
    final l = _cache.logActual(
      category: category,
      startTs: startTs,
      endTs: endTs,
      segmentId: segmentId,
      note: note,
      source: source,
    );
    _push();
    return l;
  }

  @override
  Habit addHabit({
    required String label,
    required String colorHex,
    HabitPolarity polarity = HabitPolarity.good,
    int? dailyTarget,
  }) {
    final h = _cache.addHabit(
      label: label,
      colorHex: colorHex,
      polarity: polarity,
      dailyTarget: dailyTarget,
    );
    _push();
    return h;
  }

  @override
  HabitEvent incrementHabit(String habitId, {CivilDate? date}) {
    final e = _cache.incrementHabit(habitId, date: date);
    _push();
    return e;
  }

  @override
  bool decrementHabit(String habitId, CivilDate date) {
    final removed = _cache.decrementHabit(habitId, date);
    if (removed) _push();
    return removed;
  }

  @override
  void restore(DaySnapshot snapshot) {
    _cache.restore(snapshot);
    _push();
  }
}
