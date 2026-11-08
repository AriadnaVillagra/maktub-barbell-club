import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'write_category_store.dart';

/// Writes of categories (F2). Creating needs [Accion.editarCatalogoClub]; changing an existing one is
/// authorized once it is loaded, because a default one needs a platform admin instead.
///
/// `POST   .../catalogo/categorias` `{nombre}` → the created category (200, active)
/// `PUT    .../catalogo/categorias/<id>` `{nombre}` → the category renamed
/// `PATCH  .../catalogo/categorias/<id>` `{estado: activo|archivado}` → the category
/// `DELETE .../catalogo/categorias/<id>` → `{resultado: borrado|archivado, id, categoria?}`: deleted when
///   nothing uses it, archived otherwise.
///
/// A change to a default category (`clubId` = `plataforma`) reaches every club. The server sets `id`, `clubId`
/// and `auditoria`. [store], [usage], [newId] and [now] are for tests.
Future<Response> createCategoryEndpoint(
  RequestContext context, {
  WriteCategoryStore? store,
  CategoryUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarCatalogoClub);
  final created = await _useCase(context, store, usage, newId, now).create(club, await leerCuerpoJson(context.request));
  return Response.json(body: created.toJson());
}

Future<Response> updateCategoryEndpoint(
  RequestContext context,
  String id, {
  WriteCategoryStore? store,
  CategoryUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final updated = await _useCase(
    context,
    store,
    usage,
    newId,
    now,
  ).rename(club, id, await leerCuerpoJson(context.request));
  return Response.json(body: updated.toJson());
}

Future<Response> setCategoryStatusEndpoint(
  RequestContext context,
  String id, {
  WriteCategoryStore? store,
  CategoryUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final updated = await _useCase(
    context,
    store,
    usage,
    newId,
    now,
  ).setStatus(club, id, await leerCuerpoJson(context.request));
  return Response.json(body: updated.toJson());
}

Future<Response> deleteCategoryEndpoint(
  RequestContext context,
  String id, {
  WriteCategoryStore? store,
  CategoryUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final result = await _useCase(context, store, usage, newId, now).remove(club, id);
  return Response.json(
    body: {
      'resultado': result.deleted ? 'borrado' : 'archivado',
      'id': id,
      if (result.archived != null) 'categoria': result.archived!.toJson(),
    },
  );
}

WriteCategory _useCase(
  RequestContext context,
  WriteCategoryStore? store,
  CategoryUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
) => WriteCategory(
  store ?? MongoWriteCategoryStore(context.read<Db>()),
  usage ?? MongoCategoryUsage(context.read<Db>()),
  newId: newId,
  now: now,
);

/// What [WriteCategory.remove] did.
class RemoveCategoryResult {
  const RemoveCategoryResult.deleted() : deleted = true, archived = null;
  const RemoveCategoryResult.archived(Category this.archived) : deleted = false;

  final bool deleted;
  final Category? archived;
}

class WriteCategory {
  WriteCategory(this._store, this._usage, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final WriteCategoryStore _store;
  final CategoryUsage _usage;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Category> create(ClubContext club, Json body) async {
    final name = _name(body);
    final visible = await _store.visible({clubPlataforma, club.clubId});
    _rejectTakenName(name, visible);
    final category = Category(
      id: _newId(),
      clubId: club.clubId,
      name: name,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(category);
    return category;
  }

  Future<Category> rename(ClubContext club, String id, Json body) async {
    final name = _name(body);
    final visible = await _store.visible({clubPlataforma, club.clubId});
    final current = _writable(club, visible, id);
    _rejectTakenName(name, visible, exceptId: id);
    final updated = current.copyWith(
      name: name,
      auditoria: current.auditoria.modificada(club.userId, ahora: _now()),
    );
    await _store.replace(updated);
    return updated;
  }

  Future<Category> setStatus(ClubContext club, String id, Json body) async {
    final status = _status(body);
    final current = _writable(club, await _store.visible({clubPlataforma, club.clubId}), id);
    final updated = current.copyWith(
      status: status,
      auditoria: current.auditoria.modificada(club.userId, ahora: _now()),
    );
    await _store.replace(updated);
    return updated;
  }

  /// Deletes the category if nothing uses it; otherwise archives it (it keeps resolving where it is used).
  Future<RemoveCategoryResult> remove(ClubContext club, String id) async {
    final current = _writable(club, await _store.visible({clubPlataforma, club.clubId}), id);
    if (!await _usage.isUsed(current.clubId, id)) {
      await _store.delete(current.clubId, id);
      return const RemoveCategoryResult.deleted();
    }
    final archived = current.copyWith(
      status: CatalogStatus.archived,
      auditoria: current.auditoria.modificada(club.userId, ahora: _now()),
    );
    await _store.replace(archived);
    return RemoveCategoryResult.archived(archived);
  }

  String _name(Json body) {
    final raw = body['nombre'];
    final name = raw is String ? raw.trim().replaceAll(RegExp(r'\s+'), ' ') : '';
    if (name.isEmpty) throw const ErrorDeSolicitud('El nombre es obligatorio.');
    return name;
  }

  CatalogStatus _status(Json body) {
    try {
      return CatalogStatus.deCable(body['estado']);
    } on Object {
      throw const ErrorDeSolicitud('El estado debe ser "activo" o "archivado".');
    }
  }

  void _rejectTakenName(String name, List<Category> visible, {String? exceptId}) {
    if (isCategoryNameTaken(name, visible, exceptId: exceptId)) {
      throw const ErrorDeSolicitud('Ya hay una categoría con ese nombre.', estado: HttpStatus.conflict);
    }
  }

  /// The category [id] if the user can change it; 404 if not visible, 403 without permission.
  Category _writable(ClubContext club, List<Category> visible, String id) {
    final found = visible.where((c) => c.id == id && isVisibleTo(c, club.clubId)).firstOrNull;
    if (found == null) throw const ErrorDeSolicitud.noEncontrado('Categoría no encontrada.');
    club.authorizeCatalogWrite(found);
    return found;
  }
}
