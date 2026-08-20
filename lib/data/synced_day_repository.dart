import 'dart:convert';

import 'package:day_dial_core/day_dial_core.dart';
import 'package:http/http.dart' as http;

import 'mirrored_repository.dart';

/// The web companion's repository: a thin client over the desktop hub's data
/// API (SPEC §8).
///
/// It keeps an in-memory cache so the existing (synchronous) UI works unchanged,
/// and after every edit pushes the whole snapshot back to the hub via
/// `PUT /state` — the desktop persists it to SQLite, which stays the source of
/// truth. This is a **single-writer** model (good enough for one browser talking
/// to one desktop); concurrent-edit merging is the parked CRDT work.
class SyncedDayRepository extends MirroredDayRepository {
  SyncedDayRepository({
    required DaySnapshot initial,
    required this.hub,
    this.token,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       super(InMemoryDayRepository.fromSnapshot(initial));

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
  @override
  void onMutated() {
    final body = jsonEncode({'state': cache.snapshot().toJson()});
    _client
        .put(
          hub.replace(path: '/state'),
          headers: {..._auth(token), 'content-type': 'application/json'},
          body: body,
        )
        .ignore();
  }
}
