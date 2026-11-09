import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements OpenSessionStore {
  final assignments = <String, Assignment>{};
  final plans = <String, PublishedPlan>{};
  final groups = <String, List<String>>{};
  final athletes = <String, String>{};
  final sessions = <String, Session>{};
  final allRecords = <SetRecord>[];

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async =>
      assignments['$clubId/$assignmentId'];

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async =>
      plans['$clubId/$planId'];

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      groups['$clubId/$groupId'] ?? const [];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  int sequence = 0;

  String _keyOf(Session c) =>
      '${c.clubId}/${c.assignmentId}/${c.date}/${c.week}/${c.day}';

  @override
  Future<Session?> existing(Session c) async => sessions[_keyOf(c)];

  @override
  Future<Session> markChanged(String clubId, String sessionId) async {
    final entry = sessions.entries.firstWhere(
      (e) => e.value.id == sessionId && e.value.clubId == clubId,
    );
    sequence++;
    return sessions[entry.key] = Session.fromJson({
      ...entry.value.toJson(),
      'secuencia': sequence,
      'secuenciaSesion': sequence,
    });
  }

  @override
  Future<Session> openOrResume(Session c) async {
    final key = _keyOf(c);
    final old = sessions[key];
    final present = {...?old?.presentAthleteIds, ...c.presentAthleteIds};
    return sessions[key] = Session(
      id: old?.id ?? c.id,
      clubId: c.clubId,
      assignmentId: c.assignmentId,
      planId: old?.planId ?? c.planId,
      cycle: old?.cycle ?? c.cycle,
      week: c.week,
      day: c.day,
      date: c.date,
      presentAthleteIds: present.toList(),
      sequence: old?.sequence ?? 0,
      lastSessionChange: old?.lastSessionChange ?? 0,
      auditoria: old?.auditoria ?? c.auditoria,
    );
  }

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId) async => [
    for (final r in allRecords)
      if (r.clubId == clubId && r.sessionId == sessionId) r,
  ];
}

PublishedPlan _published({int days = 2}) => PublishedPlan(
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'A',
      days: [for (var i = 0; i < days; i++) const PlanDay()],
    ),
  ],
  weekAssignment: const ['A', 'A', 'A', 'A'],
  publishedAt: DateTime.utc(2026, 11, 8),
  publishedBy: 'coach',
);

/// Assignment `a1` of `club-a`, group `g1` with `ari` and `andi`, a published plan and started 2026-11-09.
_FakeStore _store({
  String clubId = 'club-a',
  AssignmentStatus status = AssignmentStatus.active,
  String planId = 'p1',
}) => _FakeStore()..seed(clubId, status: status, planId: planId);

extension on _FakeStore {
  void seed(
    String clubId, {
    AssignmentStatus status = AssignmentStatus.active,
    String planId = 'p1',
  }) {
    assignments['$clubId/a1'] = Assignment(
      id: 'a1',
      clubId: clubId,
      planId: planId,
      groupId: 'g1',
      startDate: DateTime.utc(2026, 11, 9),
      status: status,
      auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8)),
    );
    plans['$clubId/$planId'] = _published();
    groups['$clubId/g1'] = ['ari', 'andi'];
    athletes['$clubId/user-ari'] = 'ari';
  }
}

ClubContext _athlete({String clubId = 'club-a'}) => ClubContext(
  clubId: clubId,
  userId: 'user-ari',
  roles: const {Rol.atleta},
  clubType: TipoClub.club,
);

ClubContext _coach() => const ClubContext(
  clubId: 'club-a',
  userId: 'coach',
  roles: {Rol.coach},
  clubType: TipoClub.club,
);

const _date = '2026-11-18'; // Second week of the assignment.

var _ids = 0;

Future<Response> _post(
  _FakeStore store,
  Map<String, dynamic> body, {
  ClubContext? club,
  LiveBroadcast? broadcast,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost/clubes/club-a/sesiones'),
      body: jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _athlete());
  return manejarErrores()(
    (c) => openSessionEndpoint(
      c,
      store: store,
      broadcast: broadcast ?? MemoryLiveBroadcast(),
      newId: () => 'session-${_ids++}',
      now: () => DateTime.utc(2026, 11, 18, 9),
    ),
  )(context);
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

Map<String, dynamic> _body({
  Object? assignmentId = 'a1',
  Object? date = _date,
  Object? day = 1,
  Object? week,
  Object? present,
}) => {
  'asignacionId': assignmentId,
  'fecha': date,
  'dia': day,
  'semana': ?week,
  'presentes': ?present,
};

SetRecord _record(String sessionId, {double? factor, double? pctReal}) =>
    SetRecord(
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
      pctPlan: 80,
      pctReal: pctReal,
      writtenBy: 'user-ari',
      auditoria: Auditoria.nueva('user-ari', ahora: DateTime.utc(2026, 11, 18)),
    );

void main() {
  setUpAll(() => registerFallbackValue(_athlete()));

  group('opening', () {
    test('creates the session of that date, with cycle and week from it', () async {
      final store = _store();
      final response = await _post(
        store,
        _body(present: ['ari', 'andi']),
      );

      expect(response.statusCode, HttpStatus.ok);
      final json = await _json(response);
      final session = Session.fromJson(
        (json['sesion'] as Map).cast<String, dynamic>(),
      );
      expect(session.clubId, 'club-a');
      expect(session.assignmentId, 'a1');
      expect(session.planId, 'p1');
      expect(session.cycle, 1);
      expect(session.week, 2);
      expect(session.day, 1);
      expect(session.date, DateTime.utc(2026, 11, 18));
      expect(session.presentAthleteIds, ['ari', 'andi']);
      expect(session.auditoria.creadoPor, 'user-ari');
      expect(json['registros'], isEmpty);
    });

    test('opening the same assignment and date twice gives the same session', () async {
      final store = _store();

      final first = await _json(await _post(store, _body()));
      final second = await _json(await _post(store, _body()));

      expect((second['sesion'] as Map)['id'], (first['sesion'] as Map)['id']);
      expect(store.sessions, hasLength(1));
    });

    test('adds the athletes of a later open and keeps the earlier ones', () async {
      final store = _store();

      await _post(store, _body(present: ['ari']));
      final json = await _json(await _post(store, _body(present: ['andi'])));

      expect(
        (json['sesion'] as Map)['presentes'],
        unorderedEquals(['ari', 'andi']),
      );
    });

    test('returns what was recorded so far, for the resuming device', () async {
      final store = _store();
      final json = await _json(await _post(store, _body()));
      final sessionId = (json['sesion'] as Map)['id'] as String;
      store.allRecords.add(_record(sessionId));

      final resumed = await _json(await _post(store, _body()));

      expect(resumed['registros'], hasLength(1));
    });

    test('another day of the date is another session', () async {
      final store = _store();

      final first = await _json(await _post(store, _body()));
      final other = await _json(await _post(store, _body(day: 2)));

      expect((other['sesion'] as Map)['id'], isNot((first['sesion'] as Map)['id']));
    });

    test('an explicit week replaces the one of the date', () async {
      final json = await _json(await _post(_store(), _body(week: 4)));

      expect((json['sesion'] as Map)['semana'], 4);
      expect((json['sesion'] as Map)['ciclo'], 1);
    });

    test('a coach outside the group can open it', () async {
      final response = await _post(_store(), _body(), club: _coach());

      expect(response.statusCode, HttpStatus.ok);
    });
  });

  group('work factor visibility', () {
    Future<Map<dynamic, dynamic>> firstRecord(ClubContext club) async {
      final store = _store();
      final opened = await _json(await _post(store, _body(), club: club));
      store.allRecords.add(
        _record((opened['sesion'] as Map)['id'] as String, factor: 90, pctReal: 72),
      );
      final json = await _json(await _post(store, _body(), club: club));
      return (json['registros'] as List).single as Map;
    }

    test('an athlete does not get it', () async {
      final record = await firstRecord(_athlete());

      expect(record, isNot(contains('factor')));
      expect(record, isNot(contains('pctReal')));
      expect(record['kilos'], 72.5);
    });

    test('the coach does', () async {
      final record = await firstRecord(_coach());

      expect(record['factor'], 90);
      expect(record['pctReal'], 72);
    });
  });

  group('rejections', () {
    Future<void> expectStatus(
      _FakeStore store,
      Map<String, dynamic> body,
      int status, {
      ClubContext? club,
    }) async {
      final response = await _post(store, body, club: club);
      expect(response.statusCode, status, reason: await response.body());
      expect(store.sessions, isEmpty, reason: 'nothing may be written');
    }

    test('an assignment of another club is not found', () async {
      await expectStatus(_store(clubId: 'club-b'), _body(), HttpStatus.notFound);
    });

    test('an athlete cannot open a session of a group that is not theirs', () async {
      final store = _store()..groups['club-a/g1'] = ['andi'];
      await expectStatus(store, _body(), HttpStatus.notFound);
    });

    test('a user with no athlete in the club cannot open it', () async {
      final store = _store()..athletes.clear();
      await expectStatus(store, _body(), HttpStatus.notFound);
    });

    test('an ended assignment is a conflict', () async {
      await expectStatus(
        _store(status: AssignmentStatus.ended),
        _body(),
        HttpStatus.conflict,
      );
    });

    test('a plan without a published version cannot run', () async {
      final store = _store()..plans.clear();
      await expectStatus(store, _body(), HttpStatus.unprocessableEntity);
    });

    test('a day that is not in that week of the plan', () async {
      await expectStatus(
        _store(),
        _body(day: 3),
        HttpStatus.unprocessableEntity,
      );
    });

    test('a present athlete that is not in the group', () async {
      await expectStatus(
        _store(),
        _body(present: ['stranger']),
        HttpStatus.unprocessableEntity,
      );
    });

    for (final (name, body) in [
      ('without an assignment', _body(assignmentId: null)),
      ('without a date', _body(date: null)),
      ('with an impossible date', _body(date: '2026-02-30')),
      ('with a day below 1', _body(day: 0)),
      ('with a non-integer day', _body(day: 1.5)),
      ('with a week out of range', _body(week: 5)),
      ('with malformed present athletes', _body(present: 'ari')),
    ]) {
      test('$name is a bad request', () async {
        await expectStatus(_store(), body, HttpStatus.badRequest);
      });
    }
  });

  group('who is present is a change of the session', () {
    Future<List<SessionChange>> changesOf(
      _FakeStore store,
      List<Map<String, dynamic>> bodies,
    ) async {
      final broadcast = MemoryLiveBroadcast();
      final seen = <SessionChange>[];
      final sessionIds = <String>{};
      final subscriptions = <StreamSubscription<SessionChange>>[];
      for (final body in bodies) {
        // A session id is known only after its first open, so the first one is opened with no listener.
        final response = await _post(store, body, broadcast: broadcast);
        final id = (await _json(response))['sesion']['id'] as String;
        if (sessionIds.add(id)) {
          subscriptions.add(
            broadcast.changesOf('club-a', id).listen(seen.add),
          );
        }
      }
      await pumpEventQueue();
      for (final s in subscriptions) {
        await s.cancel();
      }
      return seen;
    }

    test('adding someone publishes the session with them, once', () async {
      final store = _store();

      final changes = await changesOf(store, [
        _body(present: ['ari']),
        _body(present: ['andi']),
      ]);

      expect(changes, hasLength(1));
      expect(changes.single.session!.presentAthleteIds, ['ari', 'andi']);
      expect(changes.single.sequence, 2);
    });

    test('opening again with the same people changes nothing', () async {
      final store = _store();

      final changes = await changesOf(store, [
        _body(present: ['ari']),
        _body(present: ['ari']),
      ]);

      expect(changes, isEmpty);
      expect(store.sequence, 1);
    });
  });

  final isolated = _FakeStore();
  testClubIsolation(
    'POST /clubes/{clubId}/sesiones',
    endpoint: (context) => openSessionEndpoint(
      context,
      store: isolated,
      broadcast: MemoryLiveBroadcast(),
    ),
    path: '/clubes/{clubId}/sesiones',
    action: Accion.registrar,
    method: 'POST',
    body: jsonEncode(_body()),
    seed: (clubId, marker) {
      isolated.sessions.clear();
      isolated.seed(clubId, planId: marker);
      isolated.athletes['$clubId/u1'] = 'ari';
    },
  );
}
