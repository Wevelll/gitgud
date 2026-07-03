/// Database schema (SPEC §5). Applied once on open; `IF NOT EXISTS` keeps it
/// idempotent. When the shape changes, bump [schemaVersion] and add migration
/// steps — for now v1 is the whole story.
library;

const int schemaVersion = 1;

const List<String> schemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS profiles (
    id               TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    active_days_mask INTEGER NOT NULL DEFAULT 0,
    is_default       INTEGER NOT NULL DEFAULT 0
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS segments (
    id         TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    start_min  INTEGER NOT NULL,
    end_min    INTEGER NOT NULL,
    name       TEXT NOT NULL,
    color      TEXT NOT NULL,
    sort_order INTEGER NOT NULL
  );
  ''',
  'CREATE INDEX IF NOT EXISTS idx_segments_profile ON segments(profile_id);',
  '''
  CREATE TABLE IF NOT EXISTS recurring_tasks (
    id              TEXT PRIMARY KEY,
    label           TEXT NOT NULL,
    color           TEXT NOT NULL,
    recurrence_rule TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    archived        INTEGER NOT NULL DEFAULT 0
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS task_completions (
    id           TEXT PRIMARY KEY,
    task_id      TEXT NOT NULL REFERENCES recurring_tasks(id) ON DELETE CASCADE,
    date         TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    UNIQUE(task_id, date)
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS time_logs (
    id         TEXT PRIMARY KEY,
    date       TEXT NOT NULL,
    start_ts   TEXT NOT NULL,
    end_ts     TEXT NOT NULL,
    category   TEXT NOT NULL,
    segment_id TEXT,
    note       TEXT,
    source     TEXT NOT NULL
  );
  ''',
  'CREATE INDEX IF NOT EXISTS idx_time_logs_date ON time_logs(date);',
  '''
  CREATE TABLE IF NOT EXISTS habits (
    id           TEXT PRIMARY KEY,
    label        TEXT NOT NULL,
    color        TEXT NOT NULL,
    polarity     TEXT NOT NULL,
    daily_target INTEGER,
    created_at   TEXT NOT NULL,
    archived     INTEGER NOT NULL DEFAULT 0
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS habit_events (
    id       TEXT PRIMARY KEY,
    habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    date     TEXT NOT NULL,
    ts       TEXT NOT NULL
  );
  ''',
  'CREATE INDEX IF NOT EXISTS idx_habit_events_date '
      'ON habit_events(habit_id, date);',
  '''
  CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
  ''',
];
