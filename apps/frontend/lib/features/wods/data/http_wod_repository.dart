import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/wod_draft.dart';
import '../domain/wod_repository.dart';

class HttpWodRepository implements WodRepository {
  HttpWodRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/wods';

  static String _item(String clubId, String wodId) =>
      '${_path(clubId)}/${Uri.encodeComponent(wodId)}';

  @override
  Future<List<Wod>> wods(String clubId) async {
    final json = await _client.getList(_path(clubId));
    return [
      for (final w in json) Wod.fromJson((w as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<Wod> create(String clubId, WodDraft draft) => _rejecting(
    () async =>
        Wod.fromJson(await _client.post(_path(clubId), cuerpo: draft.toBody())),
  );

  @override
  Future<Wod> save(String clubId, String wodId, WodDraft draft) => _rejecting(
    () async =>
        Wod.fromJson(await _client.put(_item(clubId, wodId), draft.toBody())),
  );

  /// A 204 has no body: [ClienteApi] answers it with an empty map.
  @override
  Future<void> delete(String clubId, String wodId) async {
    await _client.delete(_item(clubId, wodId));
  }

  Future<Wod> _rejecting(Future<Wod> Function() send) async {
    try {
      return await send();
    } on ErrorDeApi catch (e) {
      final problems = e.estado == 422 ? _parseProblems(e.cuerpo) : null;
      if (problems == null) rethrow;
      throw WodRejected(e.mensaje, problems);
    }
  }

  /// The `problemas` of a 422 body, or null when missing or holding a code this app does not know (the
  /// caller then shows the server's own message).
  static List<WodProblem>? _parseProblems(Map<String, dynamic>? body) {
    final raw = body?['problemas'];
    if (raw is! List || raw.isEmpty) return null;
    final byName = WodProblemCode.values.asNameMap();
    final problems = <WodProblem>[];
    for (final item in raw) {
      if (item is! Map) return null;
      final code = byName['${item['codigo']}'];
      if (code == null) return null;
      problems.add(
        WodProblem(
          code,
          prescriptionIndex: (item['prescripcion'] as num?)?.toInt(),
        ),
      );
    }
    return problems;
  }
}
