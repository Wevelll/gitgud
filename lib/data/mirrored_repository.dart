import 'package:day_dial_core/day_dial_core.dart';

/// A [DayRepository] that answers every read from an in-memory cache and, after
/// every write, mirrors the resulting state somewhere else — a desktop hub over
/// HTTP ([SyncedDayRepository]), or the browser's IndexedDB
/// ([PersistedDayRepository]).
///
/// The pattern is the same in both cases: apply the edit to the cache (which is
/// `core`'s [InMemoryDayRepository], so all the real logic stays there), then
/// call [onMutated]. Subclasses supply only that one method; this class exists
/// so the ~40 forwarding members aren't written twice.
///
/// The mirror is deliberately **whole-snapshot**: an edit is cheap and the
/// state is small (a day's ring plus some tasks), so there's no diffing to get
/// wrong. It is also a **single-writer** model — see [SyncedDayRepository] on
/// why concurrent-edit merging (CRDT) is parked.
abstract class MirroredDayRepository implements DayRepository {
  MirroredDayRepository(this.cache);

  /// The authoritative in-memory state. Subclasses may read it (e.g. to
  /// serialize a snapshot) but should not mutate it directly.
  final InMemoryDayRepository cache;

  /// Called after every mutation, with the cache already updated. Must not
  /// throw: a failed mirror leaves the cache intact so the UI keeps working.
  void onMutated();

  // ---- reads (straight from the cache) --------------------------------------

  @override
  DayProfile activeProfile() => cache.activeProfile();
  @override
  List<DayProfile> profiles() => cache.profiles();
  @override
  DayProfile profileForDate(CivilDate date) => cache.profileForDate(date);
  @override
  DayProfile templateForDate(CivilDate date) => cache.templateForDate(date);
  @override
  List<RecurringTask> tasks() => cache.tasks();
  @override
  List<TaskCompletion> completions() => cache.completions();
  @override
  List<TimeLog> logs() => cache.logs();
  @override
  List<Habit> habits() => cache.habits();
  @override
  List<HabitEvent> habitEvents() => cache.habitEvents();
  @override
  SubBlockPlan subBlocks() => cache.subBlocks();
  @override
  DaySnapshot snapshot() => cache.snapshot();

  // ---- writes (cache first, then mirror) ------------------------------------

  @override
  void switchProfile(String profileId) {
    cache.switchProfile(profileId);
    onMutated();
  }

  @override
  void addProfile(DayProfile profile) {
    cache.addProfile(profile);
    onMutated();
  }

  @override
  void removeProfile(String id) {
    cache.removeProfile(id);
    onMutated();
  }

  @override
  void setProfileName(String id, String name) {
    cache.setProfileName(id, name);
    onMutated();
  }

  @override
  void setProfileWeekdays(String id, int activeDaysMask) {
    cache.setProfileWeekdays(id, activeDaysMask);
    onMutated();
  }

  @override
  void setDefaultProfile(String id) {
    cache.setDefaultProfile(id);
    onMutated();
  }

  @override
  DayProfile overrideForDate(CivilDate date) {
    final o = cache.overrideForDate(date);
    onMutated();
    return o;
  }

  @override
  void resetDate(CivilDate date) {
    cache.resetDate(date);
    onMutated();
  }

  @override
  Segment addBlock({
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final s = cache.addBlock(
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    onMutated();
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
    final s = cache.updateBlock(
      id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    onMutated();
    return s;
  }

  @override
  void deleteBlock(String id) {
    cache.deleteBlock(id);
    onMutated();
  }

  @override
  Segment addSubBlock({
    required String parentId,
    required String name,
    required String colorHex,
    required int startMin,
    required int endMin,
  }) {
    final s = cache.addSubBlock(
      parentId: parentId,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    onMutated();
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
    final s = cache.updateSubBlock(
      id,
      name: name,
      colorHex: colorHex,
      startMin: startMin,
      endMin: endMin,
    );
    onMutated();
    return s;
  }

  @override
  void deleteSubBlock(String id) {
    cache.deleteSubBlock(id);
    onMutated();
  }

  @override
  RecurringTask addRecurringTask({
    required String label,
    required Recurrence recurrence,
    required String colorHex,
  }) {
    final t = cache.addRecurringTask(
      label: label,
      recurrence: recurrence,
      colorHex: colorHex,
    );
    onMutated();
    return t;
  }

  @override
  RecurringTask updateRecurringTask(
    String id, {
    String? label,
    String? colorHex,
    Recurrence? recurrence,
  }) {
    final t = cache.updateRecurringTask(
      id,
      label: label,
      colorHex: colorHex,
      recurrence: recurrence,
    );
    onMutated();
    return t;
  }

  @override
  void setTaskArchived(String id, {required bool archived}) {
    cache.setTaskArchived(id, archived: archived);
    onMutated();
  }

  @override
  void deleteRecurringTask(String id) {
    cache.deleteRecurringTask(id);
    onMutated();
  }

  @override
  void completeTask(String taskId, CivilDate date) {
    cache.completeTask(taskId, date);
    onMutated();
  }

  @override
  void uncompleteTask(String taskId, CivilDate date) {
    cache.uncompleteTask(taskId, date);
    onMutated();
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
    final l = cache.logActual(
      category: category,
      startTs: startTs,
      endTs: endTs,
      segmentId: segmentId,
      note: note,
      source: source,
    );
    onMutated();
    return l;
  }

  @override
  Habit addHabit({
    required String label,
    required String colorHex,
    HabitPolarity polarity = HabitPolarity.good,
    int? dailyTarget,
  }) {
    final h = cache.addHabit(
      label: label,
      colorHex: colorHex,
      polarity: polarity,
      dailyTarget: dailyTarget,
    );
    onMutated();
    return h;
  }

  @override
  HabitEvent incrementHabit(String habitId, {CivilDate? date}) {
    final e = cache.incrementHabit(habitId, date: date);
    onMutated();
    return e;
  }

  @override
  bool decrementHabit(String habitId, CivilDate date) {
    final removed = cache.decrementHabit(habitId, date);
    if (removed) onMutated();
    return removed;
  }

  @override
  void restore(DaySnapshot snapshot) {
    cache.restore(snapshot);
    onMutated();
  }
}
