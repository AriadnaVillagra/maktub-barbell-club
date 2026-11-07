import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'get_team_store.dart';

/// `GET /clubes/{clubId}/equipo` → the club's equipment, the standard if it never saved one.
/// Any member can read it (`verCatalogoYPlanes`): athletes need it for loadable weights.
Future<Response> getTeamEndpoint(RequestContext context, {GetTeamStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final team = await GetTeam(store ?? MongoGetTeamStore(context.read<Db>()))(club);
  return Response.json(body: {...team.toJson(), 'cargables': team.cargables});
}

class GetTeam {
  GetTeam(this._store);

  final GetTeamStore _store;

  Future<Equipo> call(ClubContext club) async => await _store.find(club.clubId) ?? Equipo.estandarDe(club.clubId);
}
