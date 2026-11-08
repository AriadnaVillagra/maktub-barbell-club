import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'save_team_store.dart';

/// `PUT /clubes/{clubId}/equipo` with `{barras: [{kg, cantidad}], discos: [{kg, cantidad}]}` → the saved
/// inventory, with `cargables`. Needs `editarCatalogoClub`.
Future<Response> saveTeamEndpoint(RequestContext context, {SaveTeamStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarCatalogoClub);
  final body = await leerCuerpoJson(context.request);
  final team = await SaveTeam(store ?? MongoSaveTeamStore(context.read<Db>()))(club, body);
  return Response.json(body: {...team.toJson(), 'cargables': team.cargables});
}

class SaveTeam {
  SaveTeam(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SaveTeamStore _store;
  final DateTime Function() _now;

  Future<Equipo> call(ClubContext club, Json body) async {
    bool isItem(Object? e) => e is Map && e['kg'] is num && e['cantidad'] is num;
    final bars = body['barras'];
    final plates = body['discos'];
    if (bars is! List || plates is! List || !bars.every(isItem) || !plates.every(isItem)) {
      throw const ErrorDeSolicitud('El equipo necesita barras y discos con kg y cantidad numéricos.');
    }
    // The club is the path's, never the body's.
    final draft = Equipo.fromJson({'clubId': club.clubId, 'barras': bars, 'discos': plates});
    final problems = draft.validar();
    if (problems.isNotEmpty) throw ErrorDeSolicitud('Equipo inválido: ${problems.map((p) => p.name).join(', ')}.');

    final current = await _store.find(club.clubId);
    final now = _now();
    final audit = current?.auditoria?.modificada(club.userId, ahora: now) ?? Auditoria.nueva(club.userId, ahora: now);
    List<ItemInventario> heaviestFirst(List<ItemInventario> items) => [...items]..sort((a, b) => b.kg.compareTo(a.kg));
    final team = draft.copyWith(
      barras: heaviestFirst(draft.barras),
      discos: heaviestFirst(draft.discos),
      auditoria: audit,
    );
    await _store.upsert(team);
    return team;
  }
}
