import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'listar_store.dart';

/// `GET /clubes/{clubId}/wods` → the club's WoDs, each as `Wod.toJson()` (with its prescriptions, so the app
/// can copy one into a block), sorted by `nombre` (case-insensitive, ties broken by id). Needs
/// [Accion.planificar] (the coach). [store] is for tests.
Future<Response> listWodsEndpoint(
  RequestContext context, {
  ListWodsStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final wods = await ListWods(store ?? MongoListWodsStore(context.read<Db>()))(
    club,
  );
  return Response.json(body: wods);
}

class ListWods {
  ListWods(this._store);

  final ListWodsStore _store;

  Future<List<Json>> call(ClubContext club) async {
    final wods = [...await _store.wods(club.clubId)]
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return [for (final w in wods) w.toJson()];
  }
}
