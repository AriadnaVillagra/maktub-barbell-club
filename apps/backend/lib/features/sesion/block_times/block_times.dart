import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'block_times_store.dart';

/// `GET /clubes/{clubId}/sesiones/{sesionId}/tiempos` → 200 `{"tiempos": [BlockTime]}`, oldest start first. Needs
/// [Accion.registrar]. A coach reads any session of the club, an athlete only one they are present in (404
/// otherwise, like a session that is not in the club). [store] is for tests.
Future<Response> blockTimesEndpoint(
  RequestContext context,
  String sessionId, {
  BlockTimesStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final times = await BlockTimes(
    store ?? MongoBlockTimesStore(context.read<Db>()),
  )(club, sessionId);
  return Response.json(
    body: {
      'tiempos': [for (final t in times) t.toJson()],
    },
  );
}

class BlockTimes {
  BlockTimes(this._store);

  final BlockTimesStore _store;

  Future<List<BlockTime>> call(ClubContext club, String sessionId) async {
    const notFound = ErrorDeSolicitud.noEncontrado('Sesión no encontrada.');
    final session = await _store.session(club.clubId, sessionId);
    if (session == null) throw notFound;
    if (!club.can(Accion.planificar)) {
      final own = await _store.athleteIdOfUser(club.clubId, club.userId);
      if (own == null || !session.presentAthleteIds.contains(own)) {
        throw notFound;
      }
    }
    return _store.timesOf(club.clubId, sessionId);
  }
}
