import 'package:maktub_core/maktub_core.dart';

/// An athlete's past sessions (pedido de Ari, 2026-11-21). Read-only. Both calls throw `ErrorDeApi` with the
/// backend's message, e.g. a 404 for an athlete the user cannot read.
abstract interface class HistoryRepository {
  /// One page of the athlete's sessions, newest first, dated before [before] (the newest without it).
  Future<HistoryPage> page(String clubId, String athleteId, {DateTime? before});

  /// One session as the athlete lived it.
  Future<SessionHistory> session(
    String clubId,
    String athleteId,
    String sessionId,
  );
}
