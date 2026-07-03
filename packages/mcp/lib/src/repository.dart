/// The repository seam now lives in `core` (it is platform-agnostic and shared
/// by the UI, the MCP server, and the SQLite store). Re-exported here so
/// existing `package:day_dial_mcp` imports keep working.
export 'package:day_dial_core/day_dial_core.dart'
    show DayRepository, InMemoryDayRepository;
