/// SQLite-backed persistence for Day-Dial: a [DayRepository] whose state
/// survives restarts. Desktop/native only.
library;

export 'src/schema.dart' show schemaVersion;
export 'src/sqlite_day_repository.dart';
