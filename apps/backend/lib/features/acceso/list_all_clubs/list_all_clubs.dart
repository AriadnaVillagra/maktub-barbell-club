import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'list_all_clubs_store.dart';

/// `GET /plataforma/clubes` → `{clubes: [Club…]}`, every club of type `club` by name, so a platform admin can pick
/// one and enter it without a membership (support). Needs [Accion.listAllClubs] (platform admin). [store] is for
/// tests.
Future<Response> listAllClubsEndpoint(RequestContext context, {ListAllClubsStore? store}) async {
  context.read<PlatformContext>().authorize(Accion.listAllClubs);
  final clubs = await (store ?? MongoListAllClubsStore(context.read<Db>())).clubs();
  return Response.json(body: {'clubes': [for (final c in clubs) c.toJson()]});
}
