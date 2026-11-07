import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/catalog_admin_repository.dart';

class HttpCatalogAdminRepository implements CatalogAdminRepository {
  HttpCatalogAdminRepository(this._client);

  final ClienteApi _client;

  static String _club(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}';
  static String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<Category> createCategory(String clubId, String name) async =>
      Category.fromJson(
        await _client.post(
          '${_club(clubId)}/catalogo/categorias',
          cuerpo: {'nombre': name},
        ),
      );

  @override
  Future<Category> renameCategory(
    String clubId,
    String id,
    String name,
  ) async => Category.fromJson(
    await _client.put('${_club(clubId)}/catalogo/categorias/${_id(id)}', {
      'nombre': name,
    }),
  );

  @override
  Future<Category> setCategoryStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) async => Category.fromJson(
    await _client.patch('${_club(clubId)}/catalogo/categorias/${_id(id)}', {
      'estado': status.cable,
    }),
  );

  @override
  Future<RemovalOutcome> deleteCategory(String clubId, String id) async =>
      _outcome(
        await _client.delete('${_club(clubId)}/catalogo/categorias/${_id(id)}'),
      );

  @override
  Future<List<Temporizador>> timers(String clubId) async {
    final json = await _client.get('${_club(clubId)}/catalogo/temporizadores');
    return [
      for (final t in (json['temporizadores'] as List? ?? const []))
        Temporizador.fromJson((t as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<Temporizador> createTimer(String clubId, Temporizador draft) async =>
      Temporizador.fromJson(
        await _client.post(
          '${_club(clubId)}/temporizadores',
          cuerpo: _content(draft),
        ),
      );

  @override
  Future<Temporizador> updateTimer(String clubId, Temporizador timer) async =>
      Temporizador.fromJson(
        await _client.put('${_club(clubId)}/temporizadores/${_id(timer.id)}', {
          ..._content(timer),
          'estado': timer.estado.cable,
        }),
      );

  @override
  Future<Temporizador> archiveTimer(String clubId, String id) async =>
      Temporizador.fromJson(
        await _client.post(
          '${_club(clubId)}/temporizadores/${_id(id)}/archivar',
        ),
      );

  @override
  Future<RemovalOutcome> deleteTimer(String clubId, String id) async =>
      _outcome(
        await _client.delete('${_club(clubId)}/temporizadores/${_id(id)}'),
      );

  @override
  Future<Equipo> team(String clubId) async =>
      Equipo.fromJson(await _client.get('${_club(clubId)}/equipo'));

  @override
  Future<Equipo> saveTeam(String clubId, Equipo team) async => Equipo.fromJson(
    await _client.put('${_club(clubId)}/equipo', {
      'barraKg': team.barraKg,
      'paresDiscos': team.paresDiscos,
    }),
  );

  static Json _content(Temporizador t) => {
    'nombre': t.nombre,
    'tipo': t.tipo.cable,
    'trabajoSeg': t.trabajoSeg,
    'descansoSeg': t.descansoSeg,
    'rondas': t.rondas,
  };

  static RemovalOutcome _outcome(Json json) => json['resultado'] == 'borrado'
      ? RemovalOutcome.deleted
      : RemovalOutcome.archived;
}
