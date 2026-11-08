import 'package:maktub_core/maktub_core.dart';

/// An entry of the club's plan list (`GET /clubes/{id}/planes`).
class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.modelCount,
    this.updatedAt,
  });

  final String id;
  final String name;
  final PlanType type;
  final int modelCount;
  final DateTime? updatedAt;

  factory PlanSummary.fromJson(Json j) => PlanSummary(
    id: '${j['id']}',
    name: '${j['nombre'] ?? ''}',
    type: j['tipo'] == null ? PlanType.regular : PlanType.deCable(j['tipo']),
    modelCount: (j['cantidadModelos'] as num?)?.toInt() ?? 0,
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
}
