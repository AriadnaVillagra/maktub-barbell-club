import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/read_catalog/read_catalog.dart';
import 'package:maktub_backend/features/catalogo/read_catalog/read_catalog_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Fake store that, like Mongo, filters by the ids it is given.
class _FakeStore implements ReadCatalogStore {
  final exercisesList = <Exercise>[];
  final categoriesList = <Category>[];
  final timersList = <Temporizador>[];
  final groupsList = <MuscleGroup>[];
  final patternsList = <MovementPattern>[];

  /// When true, ignores the visibility ids (a leaky store): the use case must still hide other clubs.
  bool leaky = false;

  Iterable<T> _in<T extends DelClub>(List<T> l, Set<String> ids) => leaky ? l : l.where((d) => ids.contains(d.clubId));

  @override
  Future<List<Exercise>> exercises(Set<String> clubIds, {String? categoryId}) async =>
      _in(exercisesList, clubIds).toList();
  @override
  Future<List<Category>> categories(Set<String> clubIds) async => _in(categoriesList, clubIds).toList();
  @override
  Future<List<Temporizador>> timers(Set<String> clubIds) async => _in(timersList, clubIds).toList();
  @override
  Future<List<MuscleGroup>> muscleGroups(Set<String> clubIds) async => _in(groupsList, clubIds).toList();
  @override
  Future<List<MovementPattern>> patterns(Set<String> clubIds) async => _in(patternsList, clubIds).toList();
}

final _audit = Auditoria.nueva('u0', ahora: DateTime.utc(2026, 11, 7));

Exercise _exercise(
  String id,
  String clubId,
  String name, {
  List<String> categories = const [],
  CatalogStatus status = CatalogStatus.active,
}) => Exercise(id: id, clubId: clubId, name: name, categoryIds: categories, status: status, auditoria: _audit);

Category _category(String id, String clubId, String name) =>
    Category(id: id, clubId: clubId, name: name, auditoria: _audit);

Future<Map<String, dynamic>> _get(
  Future<Response> Function(RequestContext, [ReadCatalogStore?]) endpoint,
  _FakeStore store,
  String clubId, {
  String query = '',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(Request.get(Uri.parse('http://localhost/clubes/$clubId/catalogo/x$query')));
  when(() => context.read<ClubContext>())
      .thenReturn(ClubContext(clubId: clubId, userId: 'u1', roles: {Rol.atleta}, clubType: TipoClub.club));
  final r = await endpoint(context, store);
  expect(r.statusCode, 200);
  return jsonDecode(await r.body()) as Map<String, dynamic>;
}

List<String> _ids(Map<String, dynamic> body, String key) => [
  for (final e in body[key] as List) (e as Map)['id'] as String,
];

void main() {
  late _FakeStore store;
  setUp(() => store = _FakeStore());

  group('exercises', () {
    test('returns base and own club exercises, never another club\'s', () async {
      store.exercisesList.addAll([
        _exercise('base', clubPlataforma, 'Sentadilla'),
        _exercise('mine', 'club-a', 'Remo'),
        _exercise('other', 'club-b', 'Press'),
      ]);
      final body = await _get(listExercisesEndpoint, store, 'club-a');
      expect(_ids(body, 'ejercicios'), ['mine', 'base']);
    });

    test('a club with nothing of its own receives the whole base catalog', () async {
      store.exercisesList.addAll([
        _exercise('e1', clubPlataforma, 'B'),
        _exercise('e2', clubPlataforma, 'A'),
        _exercise('x', 'club-b', 'Z'),
      ]);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a'), 'ejercicios'), ['e2', 'e1']);
    });

    test('filters by category', () async {
      store.exercisesList.addAll([
        _exercise('e1', clubPlataforma, 'A', categories: ['fuerza', 'wod']),
        _exercise('e2', 'club-a', 'B', categories: ['wod']),
        _exercise('e3', clubPlataforma, 'C'),
      ]);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a', query: '?categoria=fuerza'), 'ejercicios'), [
        'e1',
      ]);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a', query: '?categoria=wod'), 'ejercicios'), [
        'e1',
        'e2',
      ]);
    });

    test('includes archived by default with their estado; estado filters', () async {
      store.exercisesList.addAll([
        _exercise('on', clubPlataforma, 'A'),
        _exercise('off', clubPlataforma, 'B', status: CatalogStatus.archived),
      ]);
      final all = await _get(listExercisesEndpoint, store, 'club-a');
      expect([for (final e in all['ejercicios'] as List) (e as Map)['estado']], ['activo', 'archivado']);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a', query: '?estado=activo'), 'ejercicios'), ['on']);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a', query: '?estado=archivado'), 'ejercicios'), [
        'off',
      ]);
    });

    test('rejects an unknown estado with 400', () async {
      final context = _Context();
      when(() => context.request).thenReturn(Request.get(Uri.parse('http://localhost/x?estado=raro')));
      when(() => context.read<ClubContext>())
          .thenReturn(ClubContext(clubId: 'club-a', userId: 'u1', roles: {Rol.atleta}, clubType: TipoClub.club));
      expect(listExercisesEndpoint(context, store), throwsA(isA<ErrorDeSolicitud>()));
    });

    test('hides other clubs even if the store leaks them', () async {
      store
        ..leaky = true
        ..exercisesList.addAll([_exercise('base', clubPlataforma, 'A'), _exercise('other', 'club-b', 'B')]);
      expect(_ids(await _get(listExercisesEndpoint, store, 'club-a'), 'ejercicios'), ['base']);
    });
  });

  test('categories: base + own, other club hidden', () async {
    store.categoriesList.addAll([
      _category('c1', clubPlataforma, 'fuerza'),
      _category('c2', 'club-a', 'accesorio'),
      _category('c3', 'club-b', 'wod'),
    ]);
    expect(_ids(await _get(listCategoriesEndpoint, store, 'club-a'), 'categorias'), ['c2', 'c1']);
  });

  test('timers: base + own, other club hidden', () async {
    Temporizador t(String id, String clubId) => Temporizador(
      id: id,
      clubId: clubId,
      nombre: id,
      tipo: TipoTemporizador.emom,
      trabajoSeg: 60,
      auditoria: _audit,
    );
    store.timersList.addAll([t('t1', clubPlataforma), t('t2', 'club-a'), t('t3', 'club-b')]);
    expect(_ids(await _get(listTimersEndpoint, store, 'club-a'), 'temporizadores'), ['t1', 't2']);
  });

  test('muscle groups and patterns: base + own, other club hidden', () async {
    store.groupsList.addAll([
      MuscleGroup(id: 'g1', clubId: clubPlataforma, name: 'Hombro', auditoria: _audit),
      MuscleGroup(id: 'g2', clubId: 'club-a', name: 'Deltoides lateral', parentId: 'g1', auditoria: _audit),
      MuscleGroup(id: 'g3', clubId: 'club-b', name: 'Otro', auditoria: _audit),
    ]);
    store.patternsList.addAll([
      MovementPattern(id: 'p1', clubId: clubPlataforma, name: 'Sentadilla', auditoria: _audit),
      MovementPattern(id: 'p3', clubId: 'club-b', name: 'Otro', auditoria: _audit),
    ]);
    expect(_ids(await _get(listMuscleGroupsEndpoint, store, 'club-a'), 'grupos'), ['g2', 'g1']);
    expect(_ids(await _get(listPatternsEndpoint, store, 'club-a'), 'patrones'), ['p1']);
  });

  group('isolation', () {
    final s = _FakeStore();
    testClubIsolation(
      'GET catalogo/ejercicios',
      endpoint: (c) => listExercisesEndpoint(c, s),
      path: '/clubes/{clubId}/catalogo/ejercicios',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) => s.exercisesList.add(_exercise('e-$marker', clubId, marker)),
    );
    testClubIsolation(
      'GET catalogo/categorias',
      endpoint: (c) => listCategoriesEndpoint(c, s),
      path: '/clubes/{clubId}/catalogo/categorias',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) => s.categoriesList.add(_category('c-$marker', clubId, marker)),
    );
    testClubIsolation(
      'GET catalogo/temporizadores',
      endpoint: (c) => listTimersEndpoint(c, s),
      path: '/clubes/{clubId}/catalogo/temporizadores',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) => s.timersList.add(
        Temporizador(id: 't-$marker', clubId: clubId, nombre: marker, tipo: TipoTemporizador.tabata, trabajoSeg: 20),
      ),
    );
    testClubIsolation(
      'GET catalogo/grupos',
      endpoint: (c) => listMuscleGroupsEndpoint(c, s),
      path: '/clubes/{clubId}/catalogo/grupos',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) =>
          s.groupsList.add(MuscleGroup(id: 'g-$marker', clubId: clubId, name: marker, auditoria: _audit)),
    );
    testClubIsolation(
      'GET catalogo/patrones',
      endpoint: (c) => listPatternsEndpoint(c, s),
      path: '/clubes/{clubId}/catalogo/patrones',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) =>
          s.patternsList.add(MovementPattern(id: 'p-$marker', clubId: clubId, name: marker, auditoria: _audit)),
    );
  });
}
