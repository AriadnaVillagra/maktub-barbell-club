import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'save_team_store.dart';

/// `PUT /clubes/{clubId}/equipo` with `{barraKg, paresDiscos}` → the saved equipment, with `cargables`.
/// Coaches only (`planificar`).
Future<Response> saveTeamEndpoint(RequestContext context, {SaveTeamStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final team = await SaveTeam(store ?? MongoSaveTeamStore(context.read<Db>()))(club, body);
  return Response.json(body: {...team.toJson(), 'cargables': team.cargables});
}

class SaveTeam {
  SaveTeam(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SaveTeamStore _store;
  final DateTime Function() _now;

  Future<Equipo> call(ClubContext club, Json body) async {
    if (body['barraKg'] is! num ||
        body['paresDiscos'] is! List ||
        (body['paresDiscos'] as List).any((d) => d is! num)) {
      throw const ErrorDeSolicitud('El equipo necesita barraKg y paresDiscos numéricos.');
    }
    // The club is the path's, never the body's.
    final draft = Equipo.fromJson({
      'clubId': club.clubId,
      'barraKg': body['barraKg'],
      'paresDiscos': body['paresDiscos'],
    });
    if (draft.paresDiscos.length > maxParesDiscos) {
      throw ErrorDeSolicitud('Un equipo admite hasta $maxParesDiscos pares de discos.');
    }
    final problems = draft.validar();
    if (problems.isNotEmpty) throw ErrorDeSolicitud('Equipo inválido: ${problems.map((p) => p.name).join(', ')}.');

    final current = await _store.find(club.clubId);
    final now = _now();
    final audit = current?.auditoria?.modificada(club.userId, ahora: now) ?? Auditoria.nueva(club.userId, ahora: now);
    final team = draft.copyWith(paresDiscos: [...draft.paresDiscos]..sort((a, b) => b.compareTo(a)), auditoria: audit);
    await _store.upsert(team);
    return team;
  }
}
