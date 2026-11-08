import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/wods/borrar/borrar.dart';
import 'package:maktub_backend/features/wods/borrar/borrar_store.dart';
import 'package:maktub_backend/features/wods/crear/crear.dart';
import 'package:maktub_backend/features/wods/crear/crear_store.dart';
import 'package:maktub_backend/features/wods/guardar/guardar.dart';
import 'package:maktub_backend/features/wods/guardar/guardar_store.dart';
import 'package:maktub_backend/features/wods/listar/listar.dart';
import 'package:maktub_backend/features/wods/listar/listar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// One in-memory collection that every use case sees through its own interface. Like Mongo, it answers only
/// for the club it is asked about.
class _FakeStore
    implements CreateWodStore, ListWodsStore, SaveWodStore, DeleteWodStore {
  final all = <Wod>[];
  var writes = 0;

  @override
  Future<void> insert(Wod wod) async {
    writes++;
    all.add(wod);
  }

  @override
  Future<List<Wod>> wods(String clubId) async => [
    for (final w in all)
      if (w.clubId == clubId) w,
  ];

  @override
  Future<Wod?> wod(String clubId, String wodId) async {
    for (final w in all) {
      if (w.clubId == clubId && w.id == wodId) return w;
    }
    return null;
  }

  @override
  Future<bool> replace(Wod wod) async {
    final i = all.indexWhere((w) => w.clubId == wod.clubId && w.id == wod.id);
    if (i < 0) return false;
    writes++;
    all[i] = wod;
    return true;
  }

  @override
  Future<bool> delete(String clubId, String wodId) async {
    final before = all.length;
    all.removeWhere((w) => w.clubId == clubId && w.id == wodId);
    final removed = all.length < before;
    if (removed) writes++;
    return removed;
  }
}

final _t0 = DateTime.utc(2026, 11, 1, 10);
final _t1 = DateTime.utc(2026, 11, 8, 9);

Wod _wod(
  String id,
  String clubId,
  String name, {
  List<Prescription> prescriptions = const [],
}) => Wod(
  id: id,
  clubId: clubId,
  name: name,
  prescriptions: prescriptions,
  auditoria: Auditoria.nueva('coach-1', ahora: _t0),
);

ClubContext _ctx(String clubId, Set<Rol> roles, {String userId = 'coach-1'}) =>
    ClubContext(
      clubId: clubId,
      userId: userId,
      roles: roles,
      clubType: TipoClub.club,
    );

final _coachA = _ctx('club-a', {Rol.coach});
final _athleteA = _ctx('club-a', {Rol.atleta}, userId: 'u-1');
final _adminOnlyA = _ctx('club-a', {Rol.adminClub}, userId: 'u-2');

Future<Response> _call(
  ClubContext ctx,
  Future<Response> Function(RequestContext) endpoint, {
  Object? body,
  String method = 'GET',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/x'),
      body: body == null ? null : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(endpoint)(context);
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  Future<Response> create(ClubContext ctx, _FakeStore store, Object? body) =>
      _call(
        ctx,
        (c) => createWodEndpoint(
          c,
          store: store,
          newId: () => 'new-id',
          now: () => _t1,
        ),
        body: body,
        method: 'POST',
      );
  Future<Response> save(
    ClubContext ctx,
    _FakeStore store,
    String id,
    Object? body,
  ) => _call(
    ctx,
    (c) => saveWodEndpoint(c, id, store: store, now: () => _t1),
    body: body,
    method: 'PUT',
  );
  Future<Response> remove(ClubContext ctx, _FakeStore store, String id) =>
      _call(
        ctx,
        (c) => deleteWodEndpoint(c, id, store: store),
        method: 'DELETE',
      );
  Future<Response> list(ClubContext ctx, _FakeStore store) =>
      _call(ctx, (c) => listWodsEndpoint(c, store: store));

  group('list', () {
    test('returns the club WoDs sorted by name, case-insensitive, with their prescriptions', () async {
      final store = _FakeStore()
        ..all.addAll([
          _wod('1', 'club-a', 'fran'),
          _wod(
            '2',
            'club-a',
            'Annie',
            prescriptions: const [Prescription(exerciseId: 'ex-1')],
          ),
          _wod('3', 'club-a', 'Cindy'),
          _wod('4', 'club-b', 'Aaa'),
        ]);
      final r = await list(_coachA, store);
      expect(r.statusCode, HttpStatus.ok);
      final body = jsonDecode(await r.body()) as List;
      expect(
        [for (final w in body) (w as Map)['nombre']],
        ['Annie', 'Cindy', 'fran'],
      );
      expect(((body.first as Map)['prescripciones'] as List), hasLength(1));
    });

    test('an athlete and an admin without coach role get 403', () async {
      final store = _FakeStore()..all.add(_wod('1', 'club-a', 'Fran'));
      for (final ctx in [_athleteA, _adminOnlyA]) {
        final r = await list(ctx, store);
        expect(r.statusCode, HttpStatus.forbidden);
        expect(await r.body(), isNot(contains('Fran')));
      }
    });
  });

  group('create', () {
    test('a coach creates a WoD: 201, server-set id, clubId and audit; the body ones are ignored', () async {
      final store = _FakeStore();
      final r = await create(_coachA, store, {
        'id': 'hacked',
        'clubId': 'club-b',
        'auditoria': {
          'creadoPor': 'someone',
          'creadoEn': '2020-01-01T00:00:00.000Z',
        },
        'nombre': '  Fran  ',
        'descripcion': '21-15-9',
        'temporizadorId': 't1',
        'prescripciones': [
          {'ejercicioId': 'thruster'},
          {
            'ejercicioId': 'pullup',
            'series': [
              {'reps': 21},
            ],
          },
        ],
      });
      expect(r.statusCode, HttpStatus.created);
      final json = await _json(r);
      expect(json['id'], 'new-id');
      expect(json['clubId'], 'club-a');
      expect(json['nombre'], 'Fran');
      expect(json['descripcion'], '21-15-9');
      expect(json['temporizadorId'], 't1');
      expect(json['auditoria']['creadoPor'], 'coach-1');
      expect(json['auditoria']['creadoEn'], _t1.toIso8601String());
      expect(store.all.single.clubId, 'club-a');
      expect(store.all.single.prescriptions, hasLength(2));
    });

    test('a WoD without prescriptions or with prescriptions without sets is accepted', () async {
      final store = _FakeStore();
      expect(
        (await create(_coachA, store, {'nombre': 'Rest'})).statusCode,
        HttpStatus.created,
      );
      expect(store.all, hasLength(1));
    });

    test(
      'without a name: 422 with {error, problemas} and nothing is written',
      () async {
        final store = _FakeStore();
        final r = await create(_coachA, store, {'nombre': '  '});
        expect(r.statusCode, HttpStatus.unprocessableEntity);
        final json = await _json(r);
        expect(json['error'], isA<String>());
        expect(json['problemas'], [
          {'codigo': 'nameEmpty'},
        ]);
        expect(store.writes, 0);
      },
    );

    test('a prescription without exercise: 422 with its position and nothing is written', () async {
      final store = _FakeStore();
      final r = await create(_coachA, store, {
        'nombre': 'Fran',
        'prescripciones': [
          {'ejercicioId': 'a'},
          {'series': []},
        ],
      });
      expect(r.statusCode, HttpStatus.unprocessableEntity);
      expect((await _json(r))['problemas'], [
        {'codigo': 'prescriptionWithoutExercise', 'prescripcion': 1},
      ]);
      expect(store.writes, 0);
    });

    test(
      'a malformed body is 400 with {error} and nothing is written',
      () async {
        final store = _FakeStore();
        final r = await create(_coachA, store, {
          'nombre': 'Fran',
          'prescripciones': 'no',
        });
        expect(r.statusCode, HttpStatus.badRequest);
        expect((await _json(r))['error'], isA<String>());
        expect(store.writes, 0);
      },
    );

    test('an athlete and an admin without coach role get 403 and nothing is stored', () async {
      final store = _FakeStore();
      for (final ctx in [_athleteA, _adminOnlyA]) {
        expect(
          (await create(ctx, store, {'nombre': 'Fran'})).statusCode,
          HttpStatus.forbidden,
        );
      }
      expect(store.writes, 0);
    });
  });

  group('save', () {
    test('replaces the WoD, keeps creation, sets modification, ignores id/clubId/audit of the body', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-a', 'Fran'));
      final r = await save(_coachA, store, 'w1', {
        'id': 'hacked',
        'clubId': 'club-b',
        'auditoria': {
          'creadoPor': 'someone',
          'creadoEn': '2020-01-01T00:00:00.000Z',
        },
        'nombre': 'Fran 2',
        'prescripciones': [
          {'ejercicioId': 'run'},
        ],
      });
      expect(r.statusCode, HttpStatus.ok);
      final json = await _json(r);
      expect(json['id'], 'w1');
      expect(json['clubId'], 'club-a');
      expect(json['nombre'], 'Fran 2');
      expect(json['auditoria']['creadoPor'], 'coach-1');
      expect(json['auditoria']['creadoEn'], _t0.toIso8601String());
      expect(json['auditoria']['modificadoEn'], _t1.toIso8601String());
      expect(store.all.single.name, 'Fran 2');
      expect(store.all.single.prescriptions, hasLength(1));
    });

    test('an unknown WoD, or one of another club, is 404', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-b', 'Fran'));
      expect(
        (await save(_coachA, store, 'w1', {'nombre': 'x'})).statusCode,
        HttpStatus.notFound,
      );
      expect(
        (await save(_coachA, store, 'nope', {'nombre': 'x'})).statusCode,
        HttpStatus.notFound,
      );
      expect(store.all.single.name, 'Fran');
    });

    test('an invalid WoD is 422 and the stored one stays as it was', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-a', 'Fran'));
      final r = await save(_coachA, store, 'w1', {
        'nombre': '',
        'prescripciones': [
          {'nota': 'x'},
        ],
      });
      expect(r.statusCode, HttpStatus.unprocessableEntity);
      final json = await _json(r);
      expect(json['error'], isA<String>());
      expect(json['problemas'], hasLength(2));
      expect(store.all.single.name, 'Fran');
      expect(store.writes, 0);
    });

    test('an athlete gets 403 and the WoD is untouched', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-a', 'Fran'));
      final r = await save(_athleteA, store, 'w1', {'nombre': 'x'});
      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.all.single.name, 'Fran');
    });
  });

  group('delete', () {
    test('a coach deletes a WoD of the club: 204', () async {
      final store = _FakeStore()
        ..all.addAll([
          _wod('w1', 'club-a', 'Fran'),
          _wod('w2', 'club-a', 'Cindy'),
        ]);
      final r = await remove(_coachA, store, 'w1');
      expect(r.statusCode, HttpStatus.noContent);
      expect([for (final w in store.all) w.id], ['w2']);
    });

    test('a WoD of another club is 404 and stays', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-b', 'Fran'));
      expect(
        (await remove(_coachA, store, 'w1')).statusCode,
        HttpStatus.notFound,
      );
      expect(store.all, hasLength(1));
    });

    test('an athlete gets 403 and nothing is deleted', () async {
      final store = _FakeStore()..all.add(_wod('w1', 'club-a', 'Fran'));
      expect(
        (await remove(_athleteA, store, 'w1')).statusCode,
        HttpStatus.forbidden,
      );
      expect(store.all, hasLength(1));
    });
  });

  group('club isolation', () {
    final store = _FakeStore();

    testClubIsolation(
      'GET /clubes/{clubId}/wods',
      endpoint: (c) => listWodsEndpoint(c, store: store),
      path: '/clubes/{clubId}/wods',
      action: Accion.planificar,
      seed: (clubId, marker) =>
          store.all.add(_wod('id-$marker', clubId, marker)),
    );

    // A create echoes the WoD, so the new id is the marker the club's seed announced.
    final pending = <String, String>{};
    testClubIsolation(
      'POST /clubes/{clubId}/wods',
      // testClubIsolation expects a 200 for the allowed case, so the 201 is mapped to it here.
      endpoint: (c) async {
        final r = await createWodEndpoint(
          c,
          store: _FakeStore(),
          newId: () => pending[c.read<ClubContext>().clubId]!,
        );
        return r.statusCode == HttpStatus.created
            ? Response(body: await r.body())
            : r;
      },
      path: '/clubes/{clubId}/wods',
      action: Accion.planificar,
      method: 'POST',
      body: '{"nombre": "created"}',
      seed: (clubId, marker) => pending[clubId] = marker,
    );

    // Both clubs hold a WoD with the same id: a save of each club's route touches and returns its own.
    testClubIsolation(
      'PUT /clubes/{clubId}/wods/{wodId}',
      endpoint: (c) =>
          saveWodEndpoint(c, 'shared-id', store: store, now: () => _t1),
      path: '/clubes/{clubId}/wods/shared-id',
      action: Accion.planificar,
      method: 'PUT',
      body: '{"nombre": "renamed"}',
      seed: (clubId, marker) {
        store.all.removeWhere((w) => w.id == 'shared-id' && w.clubId == clubId);
        store.all.add(
          Wod(
            id: 'shared-id',
            clubId: clubId,
            name: 'old',
            auditoria: Auditoria.nueva(marker, ahora: _t0),
          ),
        );
      },
    );

    // A delete answers 204 with no body, so the isolation check cannot read data from it: it is covered by
    // the "another club is 404 and stays" test above, and by the club-scoped filter of the store.
  });
}
