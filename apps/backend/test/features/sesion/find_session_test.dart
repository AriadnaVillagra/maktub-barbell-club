import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/find_session/find_session.dart';
import 'package:maktub_backend/features/sesion/find_session/find_session_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Read-only by construction: the interface has no write, so a test can only check what comes back.
class _FakeStore implements FindSessionStore {
  final assignments = <String, Assignment>{};
  final groups = <String, List<String>>{};
  final athletes = <String, String>{};
  final sessions = <Session>[];
  final allRecords = <SetRecord>[];

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async =>
      assignments['$clubId/$assignmentId'];

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      groups['$clubId/$groupId'] ?? const [];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  Future<Session?> session(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  }) async => sessions
      .where(
        (s) =>
            s.clubId == clubId &&
            s.assignmentId == assignmentId &&
            s.date == date &&
            s.week == week &&
            s.day == day,
      )
      .firstOrNull;

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId) async => [
    for (final r in allRecords)
      if (r.clubId == clubId && r.sessionId == sessionId) r,
  ];

  void seed(String clubId, {String groupId = 'g1'}) {
    assignments['$clubId/a1'] = Assignment(
      id: 'a1',
      clubId: clubId,
      planId: 'p1',
      groupId: groupId,
      startDate: DateTime.utc(2026, 11, 9),
      auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8)),
    );
    groups['$clubId/g1'] = ['ari', 'andi'];
    groups['$clubId/g2'] = ['otro'];
    athletes['$clubId/user-ari'] = 'ari';
  }

  Session addSession(
    String clubId, {
    String id = 's1',
    int week = 2,
    int day = 1,
    String planId = 'p1',
  }) {
    final s = Session(
      id: id,
      clubId: clubId,
      assignmentId: 'a1',
      planId: planId,
      cycle: 1,
      week: week,
      day: day,
      date: DateTime.utc(2026, 11, 18),
      presentAthleteIds: const ['ari'],
      auditoria: Auditoria.nueva('user-ari', ahora: DateTime.utc(2026, 11, 18)),
    );
    sessions.add(s);
    return s;
  }
}

ClubContext _athlete() => const ClubContext(
  clubId: 'club-a',
  userId: 'user-ari',
  roles: {Rol.atleta},
  clubType: TipoClub.club,
);

ClubContext _coach() => const ClubContext(
  clubId: 'club-a',
  userId: 'coach',
  roles: {Rol.coach},
  clubType: TipoClub.club,
);

const _query = 'asignacionId=a1&fecha=2026-11-18&dia=1&semana=2';

Future<Response> _get(
  _FakeStore store, {
  String query = _query,
  ClubContext? club,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request('GET', Uri.parse('http://localhost/clubes/club-a/sesiones?$query')),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _athlete());
  return manejarErrores()(
    (c) => findSessionEndpoint(c, store: store),
  )(context);
}

SetRecord _record(String sessionId, {double? factor}) => SetRecord(
  id: 'r1',
  clubId: 'club-a',
  sessionId: sessionId,
  athleteId: 'ari',
  exerciseId: 'squat',
  exerciseName: 'Sentadilla',
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: 0,
  kg: 72.5,
  workFactor: factor,
  done: true,
  writtenBy: 'user-ari',
  auditoria: Auditoria.nueva('user-ari', ahora: DateTime.utc(2026, 11, 18)),
);

void main() {
  test('returns the session of that day with its records', () async {
    final store = _FakeStore()..seed('club-a');
    store.addSession('club-a');
    store.allRecords.add(_record('s1'));

    final response = await _get(store);

    expect(response.statusCode, HttpStatus.ok);
    final json = jsonDecode(await response.body()) as Map<String, dynamic>;
    expect((json['sesion'] as Map)['id'], 's1');
    expect((json['registros'] as List).single, containsPair('kilos', 72.5));
  });

  test('204 without body when there is none, and it creates nothing', () async {
    final store = _FakeStore()..seed('club-a');

    final response = await _get(store);

    expect(response.statusCode, HttpStatus.noContent);
    expect(await response.body(), isEmpty);
    expect(store.sessions, isEmpty);
  });

  test('another day or week of the date is not that session', () async {
    final store = _FakeStore()..seed('club-a');
    store.addSession('club-a');

    expect(
      (await _get(store, query: 'asignacionId=a1&fecha=2026-11-18&dia=2'))
          .statusCode,
      HttpStatus.noContent,
    );
    expect(
      (await _get(
        store,
        query: 'asignacionId=a1&fecha=2026-11-18&dia=1&semana=3',
      )).statusCode,
      HttpStatus.noContent,
    );
  });

  test('without a week, the week of the date is used', () async {
    final store = _FakeStore()..seed('club-a');
    store.addSession('club-a'); // 2026-11-18 is in week 2

    final response = await _get(
      store,
      query: 'asignacionId=a1&fecha=2026-11-18&dia=1',
    );

    expect(response.statusCode, HttpStatus.ok);
  });

  test('work factors are hidden from an athlete and shown to a coach', () async {
    final store = _FakeStore()..seed('club-a');
    store.addSession('club-a');
    store.allRecords.add(_record('s1', factor: 95));

    Future<Map> record(ClubContext club) async {
      final json =
          jsonDecode(await (await _get(store, club: club)).body())
              as Map<String, dynamic>;
      return (json['registros'] as List).single as Map;
    }

    expect(await record(_athlete()), isNot(contains('factor')));
    expect(await record(_coach()), containsPair('factor', 95));
  });

  test('an athlete of another group gets 404', () async {
    final store = _FakeStore()..seed('club-a', groupId: 'g2');
    store.addSession('club-a');

    final response = await _get(store);

    expect(response.statusCode, HttpStatus.notFound);
  });

  test('a coach outside the group gets it', () async {
    final store = _FakeStore()..seed('club-a', groupId: 'g2');
    store.addSession('club-a');

    final response = await _get(store, club: _coach());

    expect(response.statusCode, HttpStatus.ok);
  });

  test('an assignment of another club is not found', () async {
    final store = _FakeStore()..seed('club-b');

    final response = await _get(store);

    expect(response.statusCode, HttpStatus.notFound);
  });

  for (final (name, query) in [
    ('without assignment', 'fecha=2026-11-18&dia=1'),
    ('a bad date', 'asignacionId=a1&fecha=2026-13-01&dia=1'),
    ('a day 0', 'asignacionId=a1&fecha=2026-11-18&dia=0'),
    ('a week 5', 'asignacionId=a1&fecha=2026-11-18&dia=1&semana=5'),
  ]) {
    test('$name is a bad request', () async {
      final store = _FakeStore()..seed('club-a');
      expect(
        (await _get(store, query: query)).statusCode,
        HttpStatus.badRequest,
      );
    });
  }

  final isolated = _FakeStore();
  testClubIsolation(
    'GET /clubes/{clubId}/sesiones',
    endpoint: (context) => findSessionEndpoint(context, store: isolated),
    path: '/clubes/{clubId}/sesiones?$_query',
    action: Accion.registrar,
    seed: (clubId, marker) {
      isolated.sessions.removeWhere((s) => s.clubId == clubId);
      isolated.seed(clubId);
      isolated.athletes['$clubId/u1'] = 'ari';
      isolated.addSession(clubId, planId: marker);
    },
  );
}
