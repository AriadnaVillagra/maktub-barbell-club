import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'listar_store.dart';

/// `GET /clubes/{clubId}/grupos` → the club's groups, each as `AthleteGroup.toJson()` (`id`, `clubId`, `nombre`,
/// `miembros` as athlete ids, `auditoria`), sorted by `nombre` (case-insensitive, ties broken by id). Needs
/// [Accion.verCatalogoYPlanes]: the coach and the athletes of the club. There is no endpoint to create, edit
/// or delete groups: the seeding script creates them (D14). [store] is for tests.
Future<Response> listGroupsEndpoint(
  RequestContext context, {
  ListGroupsStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final groups = await ListGroups(
    store ?? MongoListGroupsStore(context.read<Db>()),
  )(club);
  return Response.json(body: groups);
}

class ListGroups {
  ListGroups(this._store);

  final ListGroupsStore _store;

  Future<List<Json>> call(ClubContext club) async {
    final groups = [...await _store.groups(club.clubId)]
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return [for (final g in groups) g.toJson()];
  }
}
