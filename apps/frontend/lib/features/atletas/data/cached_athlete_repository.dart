import '../../../core/offline/local_copy.dart';
import '../domain/athlete_repository.dart';

/// The club's athletes with the device's copy (E7.15), so the session shows names without signal. The sheet and
/// every write go straight to the server: the kilos come already resolved in the preload.
class CachedAthleteRepository implements AthleteRepository {
  CachedAthleteRepository(this._remote, this._reads);

  final AthleteRepository _remote;
  final LocalCopyReads _reads;

  @override
  Future<List<AthleteSummary>> athletes(String clubId) => _reads.read(
    copyKey(['athletes', clubId]),
    () => _remote.athletes(clubId),
    encode: (as) => [for (final a in as) a.toJson()],
    decode: (d) => [
      for (final a in d as List)
        AthleteSummary.fromJson((a as Map).cast<String, dynamic>()),
    ],
  );

  @override
  Future<AthleteSheet> sheet(String clubId, String athleteId) =>
      _remote.sheet(clubId, athleteId);

  @override
  Future<void> addReference(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double value,
    required DateTime date,
  }) => _remote.addReference(
    clubId,
    athleteId,
    exerciseId: exerciseId,
    value: value,
    date: date,
  );

  @override
  Future<void> addFactor(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double percent,
    required DateTime date,
  }) => _remote.addFactor(
    clubId,
    athleteId,
    exerciseId: exerciseId,
    percent: percent,
    date: date,
  );

  @override
  Future<void> setFixedWeight(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double kg,
  }) => _remote.setFixedWeight(
    clubId,
    athleteId,
    exerciseId: exerciseId,
    kg: kg,
  );
}
