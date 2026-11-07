import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements WriteExerciseStore {
  final exercises = <Exercise>[];
  final categories = <Category>[];

  @override
  Future<CatalogView> view(Set<String> clubIds) async => CatalogView.of(
    exercises: exercises.where((e) => clubIds.contains(e.clubId)),
    categories: categories.where((c) => clubIds.contains(c.clubId)),
  );

  @override
  Future<void> insert(Exercise exercise) async => exercises.add(exercise);

  @override
  Future<void> replace(Exercise exercise) async {
    final i = exercises.indexWhere((e) => e.id == exercise.id && e.clubId == exercise.clubId);
    if (i >= 0) exercises[i] = exercise;
  }

  @override
  Future<void> delete(String clubId, String id) async => exercises.removeWhere((e) => e.id == id && e.clubId == clubId);
}

class _FakeUsage implements ExerciseUsage {
  final used = <String>{};

  @override
  Future<bool> isUsed(String clubId, String exerciseId) async => used.contains(exerciseId);
}

final _audit = Auditoria.nueva('u0', ahora: DateTime.utc(2026, 11, 1));
final _at = DateTime.utc(2026, 11, 7, 12);

Exercise _exercise(
  String id,
  String clubId,
  String name, {
  List<Metric> metrics = const [Metric.loadPctRm, Metric.reps],
  LoadReference reference = const LoadReference.none(),
}) => Exercise(id: id, clubId: clubId, name: name, metrics: metrics, loadReference: reference, auditoria: _audit);

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
      Uri.parse('http://localhost/clubes/${club.clubId}/catalogo/ejercicios'),
      body: body == null ? null : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club);
  return Future.sync(() => manejarErrores()(endpoint)(context));
}

Map<String, dynamic> _body(String name, {Map<String, dynamic>? extra}) => {
  'nombre': name,
  'metricas': ['carga_pct_rm', 'repeticiones'],
  ...?extra,
};

void main() {
  late _FakeStore store;
  late _FakeUsage usage;
  setUp(() {
    store = _FakeStore();
    usage = _FakeUsage();
  });

  Future<Response> create(Object body, {ClubContext? club}) => _call(
    (c) => createExerciseEndpoint(c, store: store, usage: usage, newId: () => 'new-1', now: () => _at),
    club ?? _club('club-a'),
    body: body,
  );
  Future<Response> update(String id, Object body, {ClubContext? club}) => _call(
    (c) => updateExerciseEndpoint(c, id, store: store, usage: usage, now: () => _at),
    club ?? _club('club-a'),
    method: 'PUT',
    body: body,
  );
  Future<Response> status(String id, String estado) => _call(
    (c) => setExerciseStatusEndpoint(c, id, store: store, usage: usage, now: () => _at),
    _club('club-a'),
    method: 'PATCH',
    body: {'estado': estado},
  );
  Future<Response> remove(String id, {ClubContext? club}) => _call(
    (c) => deleteExerciseEndpoint(c, id, store: store, usage: usage, now: () => _at),
    club ?? _club('club-a'),
    method: 'DELETE',
  );
  Future<Map<String, dynamic>> json(Response r) async => jsonDecode(await r.body()) as Map<String, dynamic>;

  group('create', () {
    test('the coach creates an exercise of the club; the server sets id, club, status and audit', () async {
      final r = await create({
        ..._body('Remo  con barra'),
        'id': 'forged',
        'clubId': clubPlataforma,
        'estado': 'archivado',
      });
      expect(r.statusCode, HttpStatus.ok);
      final e = Exercise.fromJson(await json(r));
      expect(e.id, 'new-1');
      expect(e.clubId, 'club-a');
      expect(e.name, 'Remo con barra');
      expect(e.status, CatalogStatus.active);
      expect(e.auditoria.creadoPor, 'u1');
      expect(e.auditoria.creadoEn, _at);
      expect(store.exercises.single.id, 'new-1');
    });

    test('an athlete is rejected and nothing is written', () async {
      final r = await create(_body('Remo'), club: _club('club-a', roles: {Rol.atleta}));
      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.exercises, isEmpty);
    });

    test('rejects a name already used by a visible exercise, base included', () async {
      store.exercises.add(_exercise('b1', clubPlataforma, 'Sentadilla'));
      expect((await create(_body('  sentadilla '))).statusCode, HttpStatus.conflict);
    });

    test('accepts the name of an exercise of another club', () async {
      store.exercises.add(_exercise('x', 'club-b', 'Remo'));
      expect((await create(_body('Remo'))).statusCode, HttpStatus.ok);
    });

    test('rejects a missing name and a malformed body', () async {
      expect((await create({'metricas': []})).statusCode, HttpStatus.badRequest);
      expect((await create(_body('A', extra: {'metricas': 'x'}))).statusCode, HttpStatus.badRequest);
      expect(
        (await create(
          _body(
            'A',
            extra: {
              'metricas': ['nope'],
            },
          ),
        )).statusCode,
        HttpStatus.badRequest,
      );
    });

    test('rejects an own reference without load x reps', () async {
      final r = await create(
        _body(
          'Correr',
          extra: {
            'metricas': ['distancia', 'tiempo'],
            'referencia': {'tipo': 'propia'},
          },
        ),
      );
      expect(r.statusCode, HttpStatus.badRequest);
      expect(store.exercises, isEmpty);
    });

    test('accepts an own reference with load x reps', () async {
      final r = await create(
        _body(
          'Remo',
          extra: {
            'referencia': {'tipo': 'propia'},
          },
        ),
      );
      expect(r.statusCode, HttpStatus.ok);
    });

    test('suggestions must be visible to the club', () async {
      store.exercises.addAll([
        _exercise('mine', 'club-a', 'A'),
        _exercise('base', clubPlataforma, 'B'),
        _exercise('other', 'club-b', 'C'),
      ]);
      expect(
        (await create(
          _body(
            'N1',
            extra: {
              'sugerencias': ['mine', 'base'],
            },
          ),
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await create(
          _body(
            'N2',
            extra: {
              'sugerencias': ['other'],
            },
          ),
        )).statusCode,
        HttpStatus.badRequest,
      );
      expect(
        (await create(
          _body(
            'N3',
            extra: {
              'sugerencias': ['ghost'],
            },
          ),
        )).statusCode,
        HttpStatus.badRequest,
      );
    });

    test('categories must be visible to the club', () async {
      store.categories.addAll([
        Category(id: 'c-base', clubId: clubPlataforma, name: 'Fuerza', auditoria: _audit),
        Category(id: 'c-other', clubId: 'club-b', name: 'Otra', auditoria: _audit),
      ]);
      expect(
        (await create(
          _body(
            'N1',
            extra: {
              'categorias': ['c-base'],
            },
          ),
        )).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await create(
          _body(
            'N2',
            extra: {
              'categorias': ['c-other'],
            },
          ),
        )).statusCode,
        HttpStatus.badRequest,
      );
    });

    test('rejects a reference to an exercise that is not visible', () async {
      store.exercises.add(_exercise('other', 'club-b', 'C'));
      final r = await create(
        _body(
          'N',
          extra: {
            'referencia': {'tipo': 'de_otro', 'ejercicioId': 'other'},
          },
        ),
      );
      expect(r.statusCode, HttpStatus.badRequest);
    });
  });

  group('update', () {
    setUp(() => store.exercises.add(_exercise('e1', 'club-a', 'Remo')));

    test('edits the fields and stamps the audit; keeps id, club and status', () async {
      final r = await update('e1', _body('Remo pendlay', extra: {'notas': 'x', 'id': 'forged', 'clubId': 'club-b'}));
      expect(r.statusCode, HttpStatus.ok);
      final e = store.exercises.single;
      expect((e.id, e.clubId, e.name, e.notes), ('e1', 'club-a', 'Remo pendlay', 'x'));
      expect(e.auditoria.creadoPor, 'u0');
      expect(e.auditoria.modificadoPor, 'u1');
      expect(e.auditoria.modificadoEn, _at);
    });

    test('keeping its own name is not a name clash', () async {
      expect((await update('e1', _body('remo'))).statusCode, HttpStatus.ok);
    });

    test('an athlete is rejected', () async {
      final r = await update('e1', _body('X'), club: _club('club-a', roles: {Rol.atleta}));
      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.exercises.single.name, 'Remo');
    });

    test('a base exercise is not editable from a club', () async {
      store.exercises.add(_exercise('base', clubPlataforma, 'Sentadilla'));
      final r = await update('base', _body('Otra'));
      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.exercises.firstWhere((e) => e.id == 'base').name, 'Sentadilla');
    });

    test('an exercise of another club is not found', () async {
      store.exercises.add(_exercise('x', 'club-b', 'Press'));
      expect((await update('x', _body('Press 2'))).statusCode, HttpStatus.notFound);
    });

    test('rejects a direct cycle (A -> A) and a two-step cycle (A -> B -> A)', () async {
      store.exercises.add(_exercise('e2', 'club-a', 'Peso muerto', reference: const LoadReference.otherExercise('e1')));
      expect(
        (await update(
          'e1',
          _body(
            'Remo',
            extra: {
              'referencia': {'tipo': 'de_otro', 'ejercicioId': 'e1'},
            },
          ),
        )).statusCode,
        HttpStatus.badRequest,
      );
      final r = await update(
        'e1',
        _body(
          'Remo',
          extra: {
            'referencia': {'tipo': 'de_otro', 'ejercicioId': 'e2'},
          },
        ),
      );
      expect(r.statusCode, HttpStatus.badRequest);
      expect(await r.body(), contains('ciclo'));
      expect(store.exercises.firstWhere((e) => e.id == 'e1').loadReference.kind, LoadReferenceKind.none);
    });

    test('accepts a chain without a cycle', () async {
      store.exercises.add(_exercise('e2', 'club-a', 'Peso muerto'));
      final r = await update(
        'e1',
        _body(
          'Remo',
          extra: {
            'referencia': {'tipo': 'de_otro', 'ejercicioId': 'e2'},
          },
        ),
      );
      expect(r.statusCode, HttpStatus.ok);
    });
  });

  group('archive and delete', () {
    setUp(() => store.exercises.add(_exercise('e1', 'club-a', 'Remo')));

    test('deletes an exercise nobody uses', () async {
      final r = await remove('e1');
      expect((await json(r))['resultado'], 'borrado');
      expect(store.exercises, isEmpty);
    });

    test('archives instead of deleting when it is in use, and it keeps resolving', () async {
      usage.used.add('e1');
      final body = await json(await remove('e1'));
      expect(body['resultado'], 'archivado');
      expect(store.exercises.single.status, CatalogStatus.archived);
      expect((body['ejercicio'] as Map)['estado'], 'archivado');
      expect(store.exercises.single.auditoria.modificadoPor, 'u1');
    });

    test('archives and restores explicitly', () async {
      expect(Exercise.fromJson(await json(await status('e1', 'archivado'))).status, CatalogStatus.archived);
      expect(Exercise.fromJson(await json(await status('e1', 'activo'))).status, CatalogStatus.active);
      expect((await status('e1', 'otro')).statusCode, HttpStatus.badRequest);
    });

    test('a base exercise is not archived nor deleted from a club', () async {
      store.exercises.add(_exercise('base', clubPlataforma, 'Sentadilla'));
      expect((await status('base', 'archivado')).statusCode, HttpStatus.forbidden);
      expect((await remove('base')).statusCode, HttpStatus.forbidden);
      expect(store.exercises.firstWhere((e) => e.id == 'base').status, CatalogStatus.active);
    });

    test('an athlete cannot delete or archive', () async {
      final athlete = _club('club-a', roles: {Rol.atleta});
      expect((await remove('e1', club: athlete)).statusCode, HttpStatus.forbidden);
      expect(store.exercises, hasLength(1));
    });

    test('another club\'s exercise is not found', () async {
      store.exercises.add(_exercise('x', 'club-b', 'Press'));
      expect((await remove('x')).statusCode, HttpStatus.notFound);
      expect(store.exercises, hasLength(2));
    });
  });

  group('club isolation', () {
    final markers = <String, String>{};
    final isolationStore = _FakeStore();
    // The created exercise's id is the club's marker, so the response carries it.
    testClubIsolation(
      'POST /clubes/{clubId}/catalogo/ejercicios',
      endpoint: (c) => createExerciseEndpoint(
        c,
        store: isolationStore,
        usage: _FakeUsage(),
        newId: () => markers[c.read<ClubContext>().clubId]!,
      ),
      path: '/clubes/{clubId}/catalogo/ejercicios',
      action: Accion.planificar,
      method: 'POST',
      body: jsonEncode(_body('Remo')),
      seed: (clubId, marker) => markers[clubId] = marker,
    );

    testClubIsolation(
      'PATCH /clubes/{clubId}/catalogo/ejercicios/e1',
      endpoint: (c) => setExerciseStatusEndpoint(c, 'e1', store: isolationStore, usage: _FakeUsage()),
      path: '/clubes/{clubId}/catalogo/ejercicios/e1',
      action: Accion.planificar,
      method: 'PATCH',
      body: jsonEncode({'estado': 'archivado'}),
      seed: (clubId, marker) => isolationStore.exercises
        ..removeWhere((e) => e.clubId == clubId && e.id == 'e1')
        ..add(_exercise('e1', clubId, marker)),
    );

    // Used exercise: the delete archives it and the response carries the exercise (with the marker).
    testClubIsolation(
      'DELETE /clubes/{clubId}/catalogo/ejercicios/e1',
      endpoint: (c) => deleteExerciseEndpoint(c, 'e1', store: isolationStore, usage: _FakeUsage()..used.add('e1')),
      path: '/clubes/{clubId}/catalogo/ejercicios/e1',
      action: Accion.planificar,
      method: 'DELETE',
      seed: (clubId, marker) => isolationStore.exercises
        ..removeWhere((e) => e.clubId == clubId && e.id == 'e1')
        ..add(_exercise('e1', clubId, marker)),
    );
  });
}
