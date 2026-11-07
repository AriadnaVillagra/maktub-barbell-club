import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'read_catalog_store.dart';

/// Reads of the catalog visible to a club: base (`plataforma`) plus the club's own (F2 §4).
/// All of them need [Accion.verCatalogoYPlanes] (enforced by the route group's `requireAction`).
///
/// `GET .../catalogo/ejercicios?categoria=<id>&estado=activo|archivado` → `{ejercicios: [...]}`
/// `GET .../catalogo/categorias?estado=...` → `{categorias: [...]}`
/// `GET .../catalogo/temporizadores` → `{temporizadores: [...]}`
/// `GET .../catalogo/grupos` → `{grupos: [...]}`
/// `GET .../catalogo/patrones` → `{patrones: [...]}`
///
/// Archived entries are included by default, each with its `estado`, so the planner/editor can show
/// them and old plans keep resolving; `estado=activo` is what a selector asks for.
/// [store] is for tests; by default it reads Mongo through the provided [Db].
Future<Response> listExercisesEndpoint(RequestContext context, [ReadCatalogStore? store]) async {
  final club = context.read<ClubContext>();
  final items = await ReadCatalog(store ?? MongoReadCatalogStore(context.read<Db>()))
      .exercises(club.clubId, categoryId: _text(context, 'categoria'), status: _status(context));
  return Response.json(
    body: {
      'ejercicios': [for (final e in items) e.toJson()],
    },
  );
}

Future<Response> listCategoriesEndpoint(RequestContext context, [ReadCatalogStore? store]) async {
  final club = context.read<ClubContext>();
  final items = await ReadCatalog(store ?? MongoReadCatalogStore(context.read<Db>()))
      .categories(club.clubId, status: _status(context));
  return Response.json(
    body: {
      'categorias': [for (final c in items) c.toJson()],
    },
  );
}

Future<Response> listTimersEndpoint(RequestContext context, [ReadCatalogStore? store]) async {
  final club = context.read<ClubContext>();
  final items = await ReadCatalog(store ?? MongoReadCatalogStore(context.read<Db>())).timers(club.clubId);
  return Response.json(
    body: {
      'temporizadores': [for (final t in items) t.toJson()],
    },
  );
}

Future<Response> listMuscleGroupsEndpoint(RequestContext context, [ReadCatalogStore? store]) async {
  final club = context.read<ClubContext>();
  final items = await ReadCatalog(store ?? MongoReadCatalogStore(context.read<Db>())).muscleGroups(club.clubId);
  return Response.json(
    body: {
      'grupos': [for (final g in items) g.toJson()],
    },
  );
}

Future<Response> listPatternsEndpoint(RequestContext context, [ReadCatalogStore? store]) async {
  final club = context.read<ClubContext>();
  final items = await ReadCatalog(store ?? MongoReadCatalogStore(context.read<Db>())).patterns(club.clubId);
  return Response.json(
    body: {
      'patrones': [for (final p in items) p.toJson()],
    },
  );
}

String? _text(RequestContext context, String name) {
  final v = context.request.uri.queryParameters[name]?.trim();
  return v == null || v.isEmpty ? null : v;
}

CatalogStatus? _status(RequestContext context) {
  final v = _text(context, 'estado');
  if (v == null) return null;
  try {
    return CatalogStatus.deCable(v);
  } on Object {
    throw const ErrorDeSolicitud('El estado debe ser "activo" o "archivado".');
  }
}

/// Visibility rule applied on top of whatever the store returns (defense in depth): `clubId` is
/// `plataforma` or the current club. Lists come sorted by name, base first on ties.
class ReadCatalog {
  ReadCatalog(this._store);

  final ReadCatalogStore _store;

  Set<String> _visible(String clubId) => {clubPlataforma, clubId};

  List<T> _only<T extends DelClub>(Iterable<T> docs, String clubId, String Function(T) name) =>
      docs.where((d) => isVisibleTo(d, clubId)).toList()..sort((a, b) {
        final byName = name(a).toLowerCase().compareTo(name(b).toLowerCase());
        if (byName != 0) return byName;
        return (a.clubId == clubPlataforma ? 0 : 1).compareTo(b.clubId == clubPlataforma ? 0 : 1);
      });

  Future<List<Exercise>> exercises(String clubId, {String? categoryId, CatalogStatus? status}) async {
    final docs = await _store.exercises(_visible(clubId), categoryId: categoryId);
    return _only(
      docs.where(
        (e) => (categoryId == null || e.categoryIds.contains(categoryId)) && (status == null || e.status == status),
      ),
      clubId,
      (e) => e.name,
    );
  }

  Future<List<Category>> categories(String clubId, {CatalogStatus? status}) async {
    final docs = await _store.categories(_visible(clubId));
    return _only(docs.where((c) => status == null || c.status == status), clubId, (c) => c.name);
  }

  Future<List<Temporizador>> timers(String clubId) async =>
      _only(await _store.timers(_visible(clubId)), clubId, (t) => t.nombre);

  Future<List<MuscleGroup>> muscleGroups(String clubId) async =>
      _only(await _store.muscleGroups(_visible(clubId)), clubId, (g) => g.name);

  Future<List<MovementPattern>> patterns(String clubId) async =>
      _only(await _store.patterns(_visible(clubId)), clubId, (p) => p.name);
}
