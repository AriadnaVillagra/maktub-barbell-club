import 'package:maktub_core/maktub_core.dart';

/// An entry of the club's athlete list (`GET /clubes/{id}/atletas`).
class AthleteSummary {
  const AthleteSummary({
    required this.id,
    required this.userId,
    required this.name,
  });

  final String id;
  final String userId;
  final String name;

  factory AthleteSummary.fromJson(Json j) => AthleteSummary(
    id: '${j['id']}',
    userId: '${j['usuarioId']}',
    name: '${j['nombreVisible']}',
  );
}

/// An athlete's references, work factors and fixed weights, in no defined order.
class AthleteSheet {
  const AthleteSheet({
    required this.athleteId,
    this.references = const [],
    this.factors = const [],
    this.fixedWeights = const [],
  });

  final String athleteId;
  final List<Reference> references;
  final List<WorkFactor> factors;
  final List<FixedWeight> fixedWeights;

  factory AthleteSheet.fromJson(Json j) {
    List<T> list<T>(String key, T Function(Json) parse) => [
      for (final e in (j[key] as List? ?? const []))
        parse((e as Map).cast<String, dynamic>()),
    ];
    return AthleteSheet(
      athleteId: '${j['atletaId']}',
      references: list('referencias', Reference.fromJson),
      factors: list('factores', WorkFactor.fromJson),
      fixedWeights: list('kilajes', FixedWeight.fromJson),
    );
  }
}

abstract interface class AthleteRepository {
  /// The club's athletes, by name. Coach only.
  Future<List<AthleteSummary>> athletes(String clubId);

  /// Throws `ErrorDeApi` with the backend's message when the sheet is missing or not allowed.
  Future<AthleteSheet> sheet(String clubId, String athleteId);

  /// Records a new RM. It does not touch the work factor. Coach only.
  Future<void> addReference(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double value,
    required DateTime date,
  });

  /// Records a new work factor (a percent) from [date]; the earlier ones stay as history.
  Future<void> addFactor(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double percent,
    required DateTime date,
  });

  /// Sets the single fixed weight of the exercise, replacing the previous one.
  Future<void> setFixedWeight(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double kg,
  });
}
