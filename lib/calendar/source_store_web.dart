import 'source_store.dart';

/// Web store — session-only for now (no persistence). Durable web storage goes
/// through IndexedDB / hub sync (SPEC §5/§8), a later step; until then the web
/// companion re-adds calendars per session, matching its limited local-first
/// role.
CalendarSourceStore makeCalendarSourceStore({String? path}) =>
    const NullCalendarSourceStore();
