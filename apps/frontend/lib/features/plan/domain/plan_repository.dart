import 'package:maktub_core/maktub_core.dart';

/// An entry of the club's plan list (`GET /clubes/{id}/planes`).
class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.modelCount,
    this.published = false,
    this.hasUnpublishedChanges = true,
    this.updatedAt,
  });

  final String id;
  final String name;
  final PlanType type;
  final int modelCount;

  /// Whether athletes can see a version of the plan.
  final bool published;

  /// Whether the saved content differs from the published copy (always true while never published).
  final bool hasUnpublishedChanges;
  final DateTime? updatedAt;

  factory PlanSummary.fromJson(Json j) => PlanSummary(
    id: '${j['id']}',
    name: '${j['nombre'] ?? ''}',
    type: j['tipo'] == null ? PlanType.regular : PlanType.deCable(j['tipo']),
    modelCount: (j['cantidadModelos'] as num?)?.toInt() ?? 0,
    published: j['publicado'] == true,
    hasUnpublishedChanges: j['cambiosSinPublicar'] != false,
    updatedAt: j['actualizadoEn'] == null
        ? null
        : DateTime.parse('${j['actualizadoEn']}'),
  );
}

abstract interface class PlanRepository {
  /// The club's plans, by name. Coach only.
  Future<List<PlanSummary>> plans(String clubId);

  /// Creates an empty plan. Coach only.
  Future<Plan> create(
    String clubId, {
    required String name,
    required PlanType type,
  });

  /// The full plan. Throws `ErrorDeApi` with the backend's message when it does not exist.
  Future<Plan> plan(String clubId, String planId);

  /// Saves the full [plan] and returns it as stored (with its audit). Coach only. Throws
  /// [PlanRejected] when the server finds it invalid and `ErrorDeApi` for any other failure.
  Future<Plan> save(String clubId, Plan plan);

  /// Publishes the saved version of [planId] and returns the plan as stored, with its new published copy.
  /// Coach only. Throws [PlanRejected] when the saved plan has problems (422) and `ErrorDeApi` for any other
  /// failure (409 when it was saved meanwhile).
  Future<Plan> publish(String clubId, String planId);
}

/// The server refused to save or publish the plan because it is invalid (422): it lists every problem, with
/// the same [PlanProblem]s `validatePlan` returns. Nothing was written.
class PlanRejected implements Exception {
  const PlanRejected(this.message, this.problems);

  final String message;
  final List<PlanProblem> problems;

  @override
  String toString() => message;
}
