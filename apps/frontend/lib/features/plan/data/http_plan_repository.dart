import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/plan_repository.dart';

class HttpPlanRepository implements PlanRepository {
  HttpPlanRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/planes';

  @override
  Future<List<PlanSummary>> plans(String clubId) async {
    final json = await _client.getList(_path(clubId));
    return [
      for (final p in json)
        PlanSummary.fromJson((p as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<Plan> create(
    String clubId, {
    required String name,
    required PlanType type,
  }) async => Plan.fromJson(
    await _client.post(
      _path(clubId),
      cuerpo: {'nombre': name, 'tipo': type.cable},
    ),
  );

  @override
  Future<Plan> plan(String clubId, String planId) async => Plan.fromJson(
    await _client.get('${_path(clubId)}/${Uri.encodeComponent(planId)}'),
  );

  @override
  Future<Plan> save(String clubId, Plan plan) async {
    try {
      return Plan.fromJson(
        await _client.put(
          '${_path(clubId)}/${Uri.encodeComponent(plan.id)}',
          plan.toJson(),
        ),
      );
    } on ErrorDeApi catch (e) {
      final problems = e.estado == 422 ? _parseProblems(e.cuerpo) : null;
      if (problems == null) rethrow;
      throw PlanRejected(e.mensaje, problems);
    }
  }

  /// The `problemas` of a 422 body, or null when they are missing or contain a code this app does not
  /// know (the caller then shows the server's own message instead of guessing).
  static List<PlanProblem>? _parseProblems(Map<String, dynamic>? body) {
    final raw = body?['problemas'];
    if (raw is! List || raw.isEmpty) return null;
    final byName = PlanProblemCode.values.asNameMap();
    final problems = <PlanProblem>[];
    for (final item in raw) {
      if (item is! Map) return null;
      final code = byName['${item['codigo']}'];
      if (code == null) return null;
      int? at(String key) => (item[key] as num?)?.toInt();
      problems.add(
        PlanProblem(
          code,
          weekModelIndex: at('modeloSemana'),
          assignmentIndex: at('semana'),
          dayIndex: at('dia'),
          blockIndex: at('bloque'),
          prescriptionIndex: at('prescripcion'),
          setIndex: at('serie'),
        ),
      );
    }
    return problems;
  }
}
