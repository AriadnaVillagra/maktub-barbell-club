import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion/ubicacion.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion/ubicacion_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements LocationStore {
  final all = <Assignment>[];

  /// `clubId/planId` of the plans with a published version.
  final published = <String>{};

  /// `clubId/groupId`
  final groups = <String>{};

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      groups.contains('$clubId/$groupId');

  @override
  Future<Assignment?> activeAssignment(String clubId, String groupId) async {
    for (final a in all) {
      if (a.clubId == clubId &&
          a.groupId == groupId &&
          a.status == AssignmentStatus.active) {
        return a;
      }
    }
    return null;
  }

  @override
  Future<bool> planIsPublished(String clubId, String planId) async =>
      published.contains('$clubId/$planId');
}

Assignment _assignment(
  String id,
  String clubId, {
  String groupId = 'g1',
  String planId = 'p1',
  DateTime? start,
  AssignmentStatus status = AssignmentStatus.active,
}) => Assignment(
  id: id,
  clubId: clubId,
  planId: planId,
  groupId: groupId,
  startDate: start ?? DateTime.utc(2026, 11, 9),
  status: status,
  endDate: status == AssignmentStatus.ended ? DateTime.utc(2026, 11, 20) : null,
  auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 8)),
);

ClubContext _ctx(String clubId, Set<Rol> roles) => ClubContext(
  clubId: clubId,
  userId: 'u-1',
  roles: roles,
  clubType: TipoClub.club,
);

Future<Response> _get(
  _FakeStore s,
  String query, {
  ClubContext? ctx,
  String groupId = 'g1',
}) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x$query')));
  when(() => context.read<ClubContext>())
      .thenReturn(ctx ?? _ctx('club-a', {Rol.atleta}));
  return manejarErrores()((c) => groupLocationEndpoint(c, groupId, store: s))(
    context,
  );
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  _FakeStore store() => _FakeStore()
    ..published.addAll(['club-a/p1', 'club-b/p1'])
    ..groups.addAll(['club-a/g1', 'club-a/g2', 'club-b/g1'])
    ..all.add(_assignment('a1', 'club-a'));

  group('location by date', () {
    // Assignment starts 2026-11-09.
    for (final (date, cycle, week) in [
      ('2026-11-09', 1, 1),
      ('2026-11-15', 1, 1),
      ('2026-11-16', 1, 2),
      ('2026-11-30', 1, 4),
      ('2026-12-06', 1, 4),
      ('2026-12-07', 2, 1),
      ('2027-01-04', 3, 1),
      ('2026-11-08', 1, 1),
      ('2020-01-01', 1, 1),
    ]) {
      test('$date is cycle $cycle, week $week', () async {
        final r = await _get(store(), '?fecha=$date');

        expect(r.statusCode, HttpStatus.ok);
        final json = await _json(r);
        expect(json['ciclo'], cycle);
        expect(json['semana'], week);
        expect(json['fecha'], date);
        expect(json['asignacion'], {
          'id': 'a1',
          'planId': 'p1',
          'fechaInicio': '2026-11-09',
        });
      });
    }

    test('day 7 is week 2 and day 28 is cycle 2, week 1', () async {
      final s = store()
        ..all.clear()
        ..all.add(
          _assignment('a1', 'club-a', start: DateTime.utc(2026, 11, 1)),
        );
      final day7 = await _json(await _get(s, '?fecha=2026-11-08'));
      final day28 = await _json(await _get(s, '?fecha=2026-11-29'));

      expect([day7['ciclo'], day7['semana']], [1, 2]);
      expect([day28['ciclo'], day28['semana']], [2, 1]);
    });

    test('an ended assignment does not answer', () async {
      final s = store()
        ..all.clear()
        ..all.add(_assignment('a1', 'club-a', status: AssignmentStatus.ended));
      final r = await _get(s, '?fecha=2026-11-10');

      expect(r.statusCode, HttpStatus.ok);
      expect(await _json(r), {'fecha': '2026-11-10', 'asignacion': null});
    });

    test(
      'only the active one answers when there is an ended one too',
      () async {
        final s = store()
          ..all.insert(
            0,
            _assignment(
              'old',
              'club-a',
              start: DateTime.utc(2026, 1, 1),
              status: AssignmentStatus.ended,
            ),
          );
        final json = await _json(await _get(s, '?fecha=2026-11-10'));

        expect(json['asignacion']['id'], 'a1');
      },
    );

    test('a group with no assignment gets an empty result', () async {
      final r = await _get(store(), '?fecha=2026-11-10', groupId: 'g2');

      expect(r.statusCode, HttpStatus.ok);
      expect(await _json(r), {'fecha': '2026-11-10', 'asignacion': null});
    });

    test('an unknown group, or one of another club, is 404', () async {
      for (final id in ['zz', 'g-b']) {
        final s = store()..groups.add('club-b/g-b');
        final r = await _get(s, '?fecha=2026-11-10', groupId: id);
        expect(r.statusCode, HttpStatus.notFound, reason: id);
      }
    });

    test('a missing or malformed fecha is 400', () async {
      for (final q in [
        '',
        '?fecha=',
        '?fecha=10/11/2026',
        '?fecha=2026-02-30',
      ]) {
        final r = await _get(store(), q);
        expect(r.statusCode, HttpStatus.badRequest, reason: q);
        expect((await _json(r))['error'], isA<String>());
      }
    });

    test(
      'an active assignment whose plan has no published copy is 422',
      () async {
        final s = store()..published.clear();
        final r = await _get(s, '?fecha=2026-11-10');

        expect(r.statusCode, HttpStatus.unprocessableEntity);
      },
    );

    test(
      'coach and athlete can read it; a role without access gets 403',
      () async {
        for (final roles in [
          {Rol.coach},
          {Rol.atleta},
        ]) {
          final r = await _get(
            store(),
            '?fecha=2026-11-10',
            ctx: _ctx('club-a', roles),
          );
          expect(r.statusCode, HttpStatus.ok, reason: '$roles');
        }
        final denied = [
          for (final r in Rol.values)
            if (!puede({r}, Accion.verCatalogoYPlanes, TipoClub.club)) r,
        ];
        for (final role in denied) {
          final r = await _get(
            store(),
            '?fecha=2026-11-10',
            ctx: _ctx('club-a', {role}),
          );
          expect(r.statusCode, HttpStatus.forbidden, reason: '$role');
        }
      },
    );

    test(
      'another club\'s assignment for the same group id is not used',
      () async {
        final s = store()
          ..all.add(
            _assignment('b1', 'club-b', start: DateTime.utc(2020, 1, 1)),
          );
        final json = await _json(await _get(s, '?fecha=2026-11-10'));

        expect(json['asignacion']['id'], 'a1');
      },
    );
  });

  group('club isolation', () {
    final s = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/grupos/{grupoId}/ubicacion',
      endpoint: (c) => groupLocationEndpoint(c, 'g1', store: s),
      path: '/clubes/{clubId}/grupos/g1/ubicacion?fecha=2026-11-10',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) {
        s.groups.add('$clubId/g1');
        s.published.add('$clubId/$marker');
        s.all.removeWhere((a) => a.clubId == clubId);
        s.all.add(_assignment('id-$marker', clubId, planId: marker));
      },
    );
  });
}
