import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/write_category/write_category.dart';
import 'package:maktub_backend/features/catalogo/write_category/write_category_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements WriteCategoryStore {
  final categories = <Category>[];

  @override
  Future<List<Category>> visible(Set<String> clubIds) async => [
    for (final c in categories)
      if (clubIds.contains(c.clubId)) c,
  ];

  @override
  Future<void> insert(Category category) async => categories.add(category);

  @override
  Future<void> replace(Category category) async {
    final i = categories.indexWhere((c) => c.id == category.id && c.clubId == category.clubId);
    if (i >= 0) categories[i] = category;
  }

  @override
  Future<void> delete(String clubId, String id) async =>
      categories.removeWhere((c) => c.id == id && c.clubId == clubId);
}

class _FakeUsage implements CategoryUsage {
  final used = <String>{};

  @override
  Future<bool> isUsed(String clubId, String categoryId) async => used.contains(categoryId);
}

final _audit = Auditoria.nueva('u0', ahora: DateTime.utc(2026, 11, 1));
final _at = DateTime.utc(2026, 11, 7, 12);

Category _category(String id, String clubId, String name) =>
    Category(id: id, clubId: clubId, name: name, auditoria: _audit);

ClubContext _club(String clubId, {Set<Rol> roles = const {Rol.coach}}) =>
    ClubContext(clubId: clubId, userId: 'u1', roles: roles, clubType: TipoClub.club);

Future<Response> _call(
  Future<Response> Function(RequestContext) endpoint,
  ClubContext club, {
  String method = 'POST',
  Object? body,
}) {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/clubes/${club.clubId}/catalogo/categorias'),
      body: body == null ? null : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club);
  return Future.sync(() => manejarErrores()(endpoint)(context));
}

void main() {
  late _FakeStore store;
  late _FakeUsage usage;
  setUp(() {
    store = _FakeStore();
    usage = _FakeUsage();
  });

  Future<Response> create(Object body, {ClubContext? club}) => _call(
    (c) => createCategoryEndpoint(c, store: store, usage: usage, newId: () => 'new-1', now: () => _at),
    club ?? _club('club-a'),
    body: body,
  );
  Future<Response> rename(String id, Object body) => _call(
    (c) => updateCategoryEndpoint(c, id, store: store, usage: usage, now: () => _at),
    _club('club-a'),
    method: 'PUT',
    body: body,
  );
  Future<Response> status(String id, String estado) => _call(
    (c) => setCategoryStatusEndpoint(c, id, store: store, usage: usage, now: () => _at),
    _club('club-a'),
    method: 'PATCH',
    body: {'estado': estado},
  );
  Future<Response> remove(String id, {ClubContext? club}) => _call(
    (c) => deleteCategoryEndpoint(c, id, store: store, usage: usage, now: () => _at),
    club ?? _club('club-a'),
    method: 'DELETE',
  );
  Future<Map<String, dynamic>> json(Response r) async => jsonDecode(await r.body()) as Map<String, dynamic>;

  group('create', () {
    test('the coach creates a category of the club with server-set fields', () async {
      final r = await create({'nombre': ' Accesorio ', 'clubId': clubPlataforma, 'id': 'forged'});
      expect(r.statusCode, HttpStatus.ok);
      final c = Category.fromJson(await json(r));
      expect((c.id, c.clubId, c.name, c.status), ('new-1', 'club-a', 'Accesorio', CatalogStatus.active));
      expect(c.auditoria.creadoPor, 'u1');
      expect(c.auditoria.creadoEn, _at);
      expect(store.categories, hasLength(1));
    });

    test('an athlete is rejected', () async {
      expect((await create({'nombre': 'X'}, club: _club('club-a', roles: {Rol.atleta}))).statusCode, 403);
      expect(store.categories, isEmpty);
    });

    test('rejects a name already visible (base or own), accepts another club\'s', () async {
      store.categories.addAll([_category('b', clubPlataforma, 'Fuerza'), _category('o', 'club-b', 'Wod')]);
      expect((await create({'nombre': 'FUERZA'})).statusCode, HttpStatus.conflict);
      expect((await create({'nombre': 'Wod'})).statusCode, HttpStatus.ok);
      expect((await create({'nombre': 'wod'})).statusCode, HttpStatus.conflict);
    });

    test('rejects an empty name', () async {
      expect((await create({'nombre': '  '})).statusCode, HttpStatus.badRequest);
      expect((await create({})).statusCode, HttpStatus.badRequest);
    });
  });

  group('edit, archive, delete', () {
    setUp(
      () => store.categories.addAll([_category('c1', 'club-a', 'Accesorio'), _category('b', clubPlataforma, 'Fuerza')]),
    );

    test('renames and stamps the audit', () async {
      expect((await rename('c1', {'nombre': 'Auxiliar'})).statusCode, HttpStatus.ok);
      final c = store.categories.firstWhere((c) => c.id == 'c1');
      expect(c.name, 'Auxiliar');
      expect(c.auditoria.modificadoPor, 'u1');
    });

    test('a base category is not editable, archivable nor deletable from a club', () async {
      expect((await rename('b', {'nombre': 'X'})).statusCode, HttpStatus.forbidden);
      expect((await status('b', 'archivado')).statusCode, HttpStatus.forbidden);
      expect((await remove('b')).statusCode, HttpStatus.forbidden);
      expect(store.categories.firstWhere((c) => c.id == 'b').name, 'Fuerza');
    });

    test('deletes a category nobody uses', () async {
      expect((await json(await remove('c1')))['resultado'], 'borrado');
      expect(store.categories.map((c) => c.id), ['b']);
    });

    test('archives instead of deleting when it is in use', () async {
      usage.used.add('c1');
      final body = await json(await remove('c1'));
      expect(body['resultado'], 'archivado');
      expect(store.categories.firstWhere((c) => c.id == 'c1').status, CatalogStatus.archived);
    });

    test('archives and restores explicitly', () async {
      expect((await status('c1', 'archivado')).statusCode, HttpStatus.ok);
      expect(store.categories.first.status, CatalogStatus.archived);
      expect((await status('c1', 'activo')).statusCode, HttpStatus.ok);
      expect((await status('c1', '???')).statusCode, HttpStatus.badRequest);
    });

    test('an athlete cannot delete; another club\'s category is not found', () async {
      expect((await remove('c1', club: _club('club-a', roles: {Rol.atleta}))).statusCode, HttpStatus.forbidden);
      store.categories.add(_category('x', 'club-b', 'Otra'));
      expect((await remove('x')).statusCode, HttpStatus.notFound);
    });
  });

  group('club isolation', () {
    final markers = <String, String>{};
    final isolationStore = _FakeStore();
    testClubIsolation(
      'POST /clubes/{clubId}/catalogo/categorias',
      endpoint: (c) => createCategoryEndpoint(
        c,
        store: isolationStore,
        usage: _FakeUsage(),
        newId: () => markers[c.read<ClubContext>().clubId]!,
      ),
      path: '/clubes/{clubId}/catalogo/categorias',
      action: Accion.planificar,
      method: 'POST',
      body: jsonEncode({'nombre': 'Accesorio'}),
      seed: (clubId, marker) => markers[clubId] = marker,
    );
    testClubIsolation(
      'PATCH /clubes/{clubId}/catalogo/categorias/c1',
      endpoint: (c) => setCategoryStatusEndpoint(c, 'c1', store: isolationStore, usage: _FakeUsage()),
      path: '/clubes/{clubId}/catalogo/categorias/c1',
      action: Accion.planificar,
      method: 'PATCH',
      body: jsonEncode({'estado': 'archivado'}),
      seed: (clubId, marker) => isolationStore.categories
        ..removeWhere((c) => c.clubId == clubId && c.id == 'c1')
        ..add(_category('c1', clubId, marker)),
    );
    testClubIsolation(
      'DELETE /clubes/{clubId}/catalogo/categorias/c1',
      endpoint: (c) => deleteCategoryEndpoint(c, 'c1', store: isolationStore, usage: _FakeUsage()..used.add('c1')),
      path: '/clubes/{clubId}/catalogo/categorias/c1',
      action: Accion.planificar,
      method: 'DELETE',
      seed: (clubId, marker) => isolationStore.categories
        ..removeWhere((c) => c.clubId == clubId && c.id == 'c1')
        ..add(_category('c1', clubId, marker)),
    );
  });
}
