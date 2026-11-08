import 'package:maktub_core/maktub_core.dart';

import 'wod_draft.dart';

/// The club's library of WoDs. Coach only: the API answers 403 to anyone else.
abstract interface class WodRepository {
  /// The club's WoDs, by name.
  Future<List<Wod>> wods(String clubId);

  /// Creates a WoD from [draft] and returns it as stored. Throws [WodRejected] when the server finds it
  /// invalid and `ErrorDeApi` for any other failure.
  Future<Wod> create(String clubId, WodDraft draft);

  /// Replaces the WoD [wodId] with [draft]. Same failures as [create]; `ErrorDeApi` with 404 when it is not in
  /// the club.
  Future<Wod> save(String clubId, String wodId, WodDraft draft);

  Future<void> delete(String clubId, String wodId);
}

/// The server refused the WoD because it is invalid (422). Nothing was written.
class WodRejected implements Exception {
  const WodRejected(this.message, this.problems);

  final String message;
  final List<WodProblem> problems;

  @override
  String toString() => message;
}
