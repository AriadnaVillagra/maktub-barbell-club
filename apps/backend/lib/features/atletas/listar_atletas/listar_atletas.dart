import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'listar_atletas_store.dart';

/// `GET /clubes/{clubId}/atletas` → `[{id, usuarioId, nombreVisible}]`, sorted alphabetically by
/// `nombreVisible` (case-insensitive, ties broken by id). [store] is for tests.
///
/// Only anyone with [Accion.verReportesDeTodos] (the coach) can list; the rest get 403. Visibility never
/// goes up: an athlete reads only their own sheet (E3.4), never the list.
Future<Response> listAthletesEndpoint(
  RequestContext context, {
  AthleteListStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verReportesDeTodos);
  final athletes = await ListAthletes(
    store ?? MongoAthleteListStore(context.read<Db>()),
  )(club);
  return Response.json(body: athletes);
}

class ListAthletes {
  ListAthletes(this._store);

  final AthleteListStore _store;

  Future<List<Json>> call(ClubContext club) async {
    final athletes = [...await _store.athletes(club.clubId)]
      ..sort((a, b) {
        final byName = a.nombreVisible.toLowerCase().compareTo(
          b.nombreVisible.toLowerCase(),
        );
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return [
      for (final a in athletes)
        {
          'id': a.id,
          'usuarioId': a.usuarioId,
          'nombreVisible': a.nombreVisible,
        },
    ];
  }
}
