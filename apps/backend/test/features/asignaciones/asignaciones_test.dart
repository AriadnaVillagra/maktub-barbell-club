import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/asignaciones/listar/listar.dart';
import 'package:maktub_backend/features/asignaciones/listar/listar_store.dart';
import 'package:maktub_backend/features/asignaciones/terminar/terminar.dart';
import 'package:maktub_backend/features/asignaciones/terminar/terminar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// One in-memory collection seen through each slice's own interface. Like Mongo, it only answers for the club
/// it is asked about, and, like the unique partial index, it refuses a second active assignment per group.
class _FakeStore
    implements CreateAssignmentStore, EndAssignmentStore, ListAssignmentsStore {
  final all = <Assignment>[];

  /// `clubId/planId` → published?
  final plans = <String, bool>{};

  /// `clubId/groupId`
  final groups = <String>{};

  @override
  Future<bool?> planIsPublished(String clubId, String planId) async =>
      plans['$clubId/$planId'];

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      groups.contains('$clubId/$groupId');

  @override
  Future<bool> insert(Assignment assignment) async {
    final taken = all.any(
      (a) =>
          a.clubId == assignment.clubId &&
          a.groupId == assignment.groupId &&
          a.status == AssignmentStatus.active &&
          assignment.status == AssignmentStatus.active,
    );
    if (taken) return false;
    all.add(assignment);
    return true;
  }

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async {
    for (final a in all) {
      if (a.clubId == clubId && a.id == assignmentId) return a;
    }
    return null;
  }

  @override
  Future<bool> end(
    String clubId,
    String assignmentId, {
    required DateTime endDate,
    required String userId,
    required DateTime at,
  }) async {
    final i = all.indexWhere(
      (a) =>
          a.clubId == clubId &&
          a.id == assignmentId &&
          a.status != AssignmentStatus.ended,
    );
    if (i < 0) return false;
    final a = all[i];
    all[i] = Assignment(
      id: a.id,
      clubId: a.clubId,
      planId: a.planId,
      groupId: a.groupId,
      startDate: a.startDate,
      status: AssignmentStatus.ended,
      endDate: endDate,
      auditoria: a.auditoria.modificada(userId, ahora: at),
    );
    return true;
  }

  @override
  Future<List<Assignment>> assignments(
    String clubId, {
    String? groupId,
  }) async => [
    for (final a in all)
      if (a.clubId == clubId && (groupId == null || a.groupId == groupId)) a,
  ];
}

final _t0 = DateTime.utc(2026, 11, 8, 10);

Assignment _assignment(
  String id,
  String clubId, {
  String groupId = 'g1',
  String planId = 'p1',
  DateTime? start,
  AssignmentStatus status = AssignmentStatus.active,
  DateTime? end,
}) => Assignment(
  id: id,
  clubId: clubId,
  planId: planId,
  groupId: groupId,
  startDate: start ?? DateTime.utc(2026, 11, 9),
  status: status,
  endDate: end,
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
final _coachB = _ctx('club-b', {Rol.coach}, userId: 'coach-2');

Future<Response> _call(
  ClubContext ctx,
  Future<Response> Function(RequestContext) endpoint, {
  String? body,
  String method = 'GET',
  String url = 'http://localhost/x',
}) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request(method, Uri.parse(url), body: body));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(endpoint)(context);
}

Future<dynamic> _json(Response r) async => jsonDecode(await r.body());

void main() {
  _FakeStore store() => _FakeStore()
    ..plans['club-a/p1'] = true
    ..plans['club-a/draft'] = false
    ..plans['club-b/p-b'] = true
    ..groups.addAll(['club-a/g1', 'club-a/g2', 'club-b/g-b']);

  group('create', () {
    var counter = 0;
    Future<Response> create(
      ClubContext ctx,
      _FakeStore s,
      Object? body, {
      String? raw,
    }) => _call(
      ctx,
      (c) => createAssignmentEndpoint(
        c,
        store: s,
        newId: () => 'a${++counter}',
        now: () => _t0,
      ),
      body: raw ?? jsonEncode(body),
      method: 'POST',
    );

    Map<String, Object?> body({
      String planId = 'p1',
      String groupId = 'g1',
      Object? start = '2026-11-09',
    }) => {'planId': planId, 'grupoId': groupId, 'fechaInicio': start};

    test('creates an active assignment: 201, UTC start date, audit', () async {
      final s = store();
      final r = await create(_coachA, s, body());

      expect(r.statusCode, HttpStatus.created);
      final json = await _json(r) as Map<String, dynamic>;
      expect(json['estado'], 'activa');
      expect(json['fechaInicio'], '2026-11-09');
      expect(json.containsKey('fechaFin'), isFalse);
      expect(json['clubId'], 'club-a');
      expect(json['planId'], 'p1');
      expect(json['grupoId'], 'g1');
      final stored = s.all.single;
      expect(stored.startDate, DateTime.utc(2026, 11, 9));
      expect(stored.startDate.isUtc, isTrue);
      expect(stored.status, AssignmentStatus.active);
      expect(stored.auditoria.creadoPor, 'coach-1');
      expect(stored.auditoria.creadoEn, _t0);
    });

    test('a clubId, estado or id sent by the client is ignored', () async {
      final s = store();
      await create(_coachA, s, {
        ...body(),
        'clubId': 'club-b',
        'estado': 'terminada',
        'id': 'forged',
        'fechaFin': '2026-11-10',
      });

      final stored = s.all.single;
      expect(stored.clubId, 'club-a');
      expect(stored.status, AssignmentStatus.active);
      expect(stored.id, isNot('forged'));
      expect(stored.endDate, isNull);
    });

    test(
      'a plan with a published version is assigned even if its draft changed',
      () async {
        // The slice never reads the draft: only whether a published version exists.
        final r = await create(_coachA, store(), body());

        expect(r.statusCode, HttpStatus.created);
      },
    );

    test('a plan never published is 422 with a Spanish error and nothing is written', () async {
      final s = store();
      final r = await create(_coachA, s, body(planId: 'draft'));

      expect(r.statusCode, HttpStatus.unprocessableEntity);
      expect((await _json(r))['error'], contains('versión publicada'));
      expect(s.all, isEmpty);
    });

    test('a plan or a group of another club, or unknown, is 404', () async {
      final s = store();
      for (final b in [
        body(planId: 'p-b'),
        body(planId: 'zz'),
        body(groupId: 'g-b'),
        body(groupId: 'zz'),
      ]) {
        final r = await create(_coachA, s, b);
        expect(r.statusCode, HttpStatus.notFound);
        expect((await _json(r))['error'], isA<String>());
      }
      expect(s.all, isEmpty);
    });

    test(
      'a second active assignment for the same group is 409 and writes nothing',
      () async {
        final s = store();
        await create(_coachA, s, body());
        final r = await create(_coachA, s, body(start: '2026-12-01'));

        expect(r.statusCode, HttpStatus.conflict);
        expect((await _json(r))['error'], contains('activa'));
        expect(s.all, hasLength(1));
        expect(s.all.single.startDate, DateTime.utc(2026, 11, 9));
      },
    );

    test('another group can have its own active assignment', () async {
      final s = store();
      await create(_coachA, s, body());
      final r = await create(_coachA, s, body(groupId: 'g2'));

      expect(r.statusCode, HttpStatus.created);
      expect(s.all, hasLength(2));
    });

    test('after ending the active one a new one can be created', () async {
      final s = store();
      await create(_coachA, s, body());
      await _call(
        _coachA,
        (c) =>
            endAssignmentEndpoint(c, s.all.single.id, store: s, now: () => _t0),
        method: 'POST',
      );
      final r = await create(_coachA, s, body(start: '2026-12-01'));

      expect(r.statusCode, HttpStatus.created);
      expect(s.all.map((a) => a.status), [
        AssignmentStatus.ended,
        AssignmentStatus.active,
      ]);
    });

    test('two requests at once for one group: exactly one wins', () async {
      final s = store();
      final results = await Future.wait([
        create(_coachA, s, body()),
        create(_coachA, s, body(start: '2026-12-01')),
      ]);

      expect(results.map((r) => r.statusCode).toList()..sort(), [
        HttpStatus.created,
        HttpStatus.conflict,
      ]);
      expect(s.all, hasLength(1));
    });

    test('bad input is 400: dates, missing ids, non-object body', () async {
      final s = store();
      for (final b in [
        body(start: null),
        body(start: '09/11/2026'),
        body(start: '2026-02-30'),
        body(start: '2026-11-9'),
        body(start: 20261109),
        body(planId: ''),
        body(groupId: '  '),
        {'planId': 'p1', 'fechaInicio': '2026-11-09'},
        {'grupoId': 'g1', 'fechaInicio': '2026-11-09'},
      ]) {
        final r = await create(_coachA, s, b);
        expect(r.statusCode, HttpStatus.badRequest, reason: '$b');
        expect((await _json(r))['error'], isA<String>());
      }
      expect((await create(_coachA, s, null, raw: '[]')).statusCode, 400);
      expect(s.all, isEmpty);
    });

    test('an athlete and an admin without coach role get 403', () async {
      final s = store();
      for (final ctx in [_athleteA, _adminOnlyA]) {
        final r = await create(ctx, s, body());
        expect(r.statusCode, HttpStatus.forbidden);
      }
      expect(s.all, isEmpty);
    });
  });

  group('end', () {
    Future<Response> end(
      ClubContext ctx,
      _FakeStore s,
      String id, {
      Object? body,
      DateTime? now,
    }) => _call(
      ctx,
      (c) => endAssignmentEndpoint(c, id, store: s, now: () => now ?? _t0),
      body: body == null ? null : jsonEncode(body),
      method: 'POST',
    );

    test(
      'ends it: terminada with today as fechaFin, nothing deleted',
      () async {
        final s = store()
          ..all.add(
            _assignment('a1', 'club-a', start: DateTime.utc(2026, 11, 1)),
          );
        final r = await end(
          _coachA,
          s,
          'a1',
          now: DateTime.utc(2026, 11, 20, 23, 30),
        );

        expect(r.statusCode, HttpStatus.ok);
        final json = await _json(r) as Map<String, dynamic>;
        expect(json['estado'], 'terminada');
        expect(json['fechaFin'], '2026-11-20');
        expect(json['auditoria']['modificadoPor'], 'coach-1');
        expect(s.all, hasLength(1));
        expect(s.all.single.status, AssignmentStatus.ended);
        expect(s.all.single.endDate, DateTime.utc(2026, 11, 20));
        expect(s.all.single.planId, 'p1');
        expect(s.all.single.startDate, DateTime.utc(2026, 11, 1));
      },
    );

    test('an explicit fechaFin is used', () async {
      final s = store()..all.add(_assignment('a1', 'club-a'));
      final r = await end(_coachA, s, 'a1', body: {'fechaFin': '2026-11-15'});

      expect(r.statusCode, HttpStatus.ok);
      expect(s.all.single.endDate, DateTime.utc(2026, 11, 15));
    });

    test('one that has not started ends on its start date', () async {
      final s = store()
        ..all.add(
          _assignment('a1', 'club-a', start: DateTime.utc(2026, 12, 1)),
        );
      await end(_coachA, s, 'a1');

      expect(s.all.single.endDate, DateTime.utc(2026, 12, 1));
    });

    test(
      'a fechaFin before the start or not a date is 400 and nothing changes',
      () async {
        final s = store()..all.add(_assignment('a1', 'club-a'));
        for (final b in [
          {'fechaFin': '2026-11-08'},
          {'fechaFin': 'mañana'},
          {'fechaFin': 5},
        ]) {
          final r = await end(_coachA, s, 'a1', body: b);
          expect(r.statusCode, HttpStatus.badRequest, reason: '$b');
        }
        expect(s.all.single.status, AssignmentStatus.active);
      },
    );

    test('ending it twice is 409 and keeps the first end date', () async {
      final s = store()..all.add(_assignment('a1', 'club-a'));
      await end(_coachA, s, 'a1', body: {'fechaFin': '2026-11-15'});
      final r = await end(_coachA, s, 'a1', body: {'fechaFin': '2026-11-20'});

      expect(r.statusCode, HttpStatus.conflict);
      expect(s.all.single.endDate, DateTime.utc(2026, 11, 15));
    });

    test('a paused assignment can be ended', () async {
      final s = store()
        ..all.add(_assignment('a1', 'club-a', status: AssignmentStatus.paused));
      final r = await end(_coachA, s, 'a1');

      expect(r.statusCode, HttpStatus.ok);
    });

    test(
      'an unknown assignment or one of another club is 404 and unchanged',
      () async {
        final s = store()..all.add(_assignment('a1', 'club-a'));
        expect((await end(_coachA, s, 'zz')).statusCode, HttpStatus.notFound);
        expect((await end(_coachB, s, 'a1')).statusCode, HttpStatus.notFound);
        expect(s.all.single.status, AssignmentStatus.active);
      },
    );

    test('an athlete and an admin without coach role get 403', () async {
      final s = store()..all.add(_assignment('a1', 'club-a'));
      for (final ctx in [_athleteA, _adminOnlyA]) {
        expect((await end(ctx, s, 'a1')).statusCode, HttpStatus.forbidden);
      }
      expect(s.all.single.status, AssignmentStatus.active);
    });
  });

  group('list', () {
    Future<Response> list(ClubContext ctx, _FakeStore s, {String query = ''}) =>
        _call(
          ctx,
          (c) => listAssignmentsEndpoint(c, store: s),
          url: 'http://localhost/x$query',
        );

    test(
      'lists active and ended assignments of the club, newest start first',
      () async {
        final s = store()
          ..all.addAll([
            _assignment(
              'a1',
              'club-a',
              start: DateTime.utc(2026, 9, 1),
              status: AssignmentStatus.ended,
              end: DateTime.utc(2026, 10, 1),
            ),
            _assignment(
              'a2',
              'club-a',
              groupId: 'g2',
              start: DateTime.utc(2026, 11, 9),
            ),
            _assignment('a3', 'club-a', start: DateTime.utc(2026, 11, 9)),
            _assignment('b1', 'club-b', groupId: 'g-b'),
          ]);
        final body = await _json(await list(_coachA, s)) as List;

        expect([for (final a in body) (a as Map)['id']], ['a2', 'a3', 'a1']);
        expect((body.last as Map)['fechaFin'], '2026-10-01');
      },
    );

    test('filters by group', () async {
      final s = store()
        ..all.addAll([
          _assignment('a1', 'club-a', groupId: 'g1'),
          _assignment('a2', 'club-a', groupId: 'g2'),
        ]);
      final body =
          await _json(await list(_coachA, s, query: '?grupoId=g2')) as List;

      expect([for (final a in body) (a as Map)['id']], ['a2']);
    });

    test(
      'an athlete of the club can read; a club without assignments gets []',
      () async {
        final s = store()..all.add(_assignment('a1', 'club-a'));
        expect((await list(_athleteA, s)).statusCode, HttpStatus.ok);
        expect(await _json(await list(_coachB, s)), isEmpty);
      },
    );
  });

  group('club isolation', () {
    final s = store();

    testClubIsolation(
      'GET /clubes/{clubId}/asignaciones',
      endpoint: (c) => listAssignmentsEndpoint(c, store: s),
      path: '/clubes/{clubId}/asignaciones',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) =>
          s.all.add(_assignment('id-$marker', clubId, groupId: marker)),
    );

    // The response echoes the assignment, so the new id is the marker the club's seed announced.
    final pending = <String, String>{};
    testClubIsolation(
      'POST /clubes/{clubId}/asignaciones',
      // testClubIsolation expects a 200 for the allowed case, so the 201 is mapped to it here.
      endpoint: (c) async {
        final r = await createAssignmentEndpoint(
          c,
          store: store()
            ..plans['${c.read<ClubContext>().clubId}/p1'] = true
            ..groups.add('${c.read<ClubContext>().clubId}/g1'),
          newId: () => pending[c.read<ClubContext>().clubId]!,
        );
        return r.statusCode == HttpStatus.created
            ? Response(body: await r.body())
            : r;
      },
      path: '/clubes/{clubId}/asignaciones',
      action: Accion.planificar,
      method: 'POST',
      body: '{"planId": "p1", "grupoId": "g1", "fechaInicio": "2026-11-09"}',
      seed: (clubId, marker) => pending[clubId] = marker,
    );

    // Both clubs hold an assignment with the same id: each club's route ends its own.
    testClubIsolation(
      'POST /clubes/{clubId}/asignaciones/{asignacionId}/terminar',
      endpoint: (c) => endAssignmentEndpoint(c, 'shared-id', store: s),
      path: '/clubes/{clubId}/asignaciones/shared-id/terminar',
      action: Accion.planificar,
      method: 'POST',
      seed: (clubId, marker) {
        s.all.removeWhere((a) => a.id == 'shared-id' && a.clubId == clubId);
        s.all.add(_assignment('shared-id', clubId, planId: marker));
      },
    );
  });
}
