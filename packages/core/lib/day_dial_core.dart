/// Day-Dial core: platform-agnostic models and time math shared by the Flutter
/// UI and the MCP server. No Flutter, no dart:io.
library;

export 'src/time/day_minutes.dart';
export 'src/time/civil_date.dart';
export 'src/models/segment.dart';
export 'src/models/day_profile.dart';
export 'src/models/ring_edit.dart';
export 'src/models/sub_block.dart';
export 'src/models/recurrence.dart';
export 'src/models/recurring_task.dart';
export 'src/models/habit.dart';
export 'src/models/time_log.dart';
export 'src/notify/transition_alert.dart';
export 'src/notify/idle_nudge.dart';
export 'src/focus/focus_session.dart';
export 'src/stats/plan_vs_actual.dart';
export 'src/stats/streaks.dart';
export 'src/stats/review.dart';
export 'src/export/csv_export.dart';
export 'src/export/ics_export.dart';
export 'src/calendar/calendar_event.dart';
export 'src/calendar/calendar_source.dart';
export 'src/calendar/ics_parser.dart';
export 'src/calendar/calendar_recurrence.dart';
export 'src/calendar/calendar_overlay.dart';
export 'src/calendar/calendar_provider.dart';
export 'src/repository/day_repository.dart';
export 'src/repository/day_snapshot.dart';
