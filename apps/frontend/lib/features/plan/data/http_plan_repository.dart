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
}
