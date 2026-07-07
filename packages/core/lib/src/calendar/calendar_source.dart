/// How a calendar is sourced (SPEC §12.1). v1 ships [caldav]/[ics] (standard
/// protocol, desktop + web) and [device] (the OS calendar the user already
/// configured, mobile). Direct OAuth providers are explicitly Later.
enum CalendarSourceKind { caldav, ics, device }

/// Configuration for one mirrored, read-only calendar (SPEC §5 `calendar_sources`).
///
/// This is the only *authored* calendar state — the events it yields are a
/// disposable cache. It carries no logic and does no I/O itself; the host layer
/// fetches ([url] for `caldav`/`ics`, [calId] for a `device` calendar) and feeds
/// the parsed events back in. Opt-in, off by default: [enabled] gates polling.
class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.kind,
    required this.name,
    this.url,
    this.calId,
    this.colorHex = '#7C7CA8',
    this.enabled = true,
    this.lastSyncTs,
  });

  final String id;
  final CalendarSourceKind kind;
  final String name;

  /// Fetch URL for [CalendarSourceKind.caldav] / [CalendarSourceKind.ics].
  final String? url;

  /// OS calendar identifier for [CalendarSourceKind.device].
  final String? calId;

  final String colorHex;
  final bool enabled;

  /// ISO-8601 timestamp of the last successful sync, or null if never synced.
  final String? lastSyncTs;

  CalendarSource copyWith({
    String? name,
    String? url,
    String? calId,
    String? colorHex,
    bool? enabled,
    String? lastSyncTs,
  }) =>
      CalendarSource(
        id: id,
        kind: kind,
        name: name ?? this.name,
        url: url ?? this.url,
        calId: calId ?? this.calId,
        colorHex: colorHex ?? this.colorHex,
        enabled: enabled ?? this.enabled,
        lastSyncTs: lastSyncTs ?? this.lastSyncTs,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        if (url != null) 'url': url,
        if (calId != null) 'calId': calId,
        'color': colorHex,
        'enabled': enabled,
        if (lastSyncTs != null) 'lastSyncTs': lastSyncTs,
      };

  factory CalendarSource.fromJson(Map<String, Object?> j) => CalendarSource(
        id: j['id'] as String,
        kind: CalendarSourceKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => CalendarSourceKind.ics,
        ),
        name: j['name'] as String,
        url: j['url'] as String?,
        calId: j['calId'] as String?,
        colorHex: j['color'] as String? ?? '#7C7CA8',
        enabled: j['enabled'] as bool? ?? true,
        lastSyncTs: j['lastSyncTs'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarSource &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.url == url &&
      other.calId == calId &&
      other.colorHex == colorHex &&
      other.enabled == enabled &&
      other.lastSyncTs == lastSyncTs;

  @override
  int get hashCode =>
      Object.hash(id, kind, name, url, calId, colorHex, enabled, lastSyncTs);
}
