import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/session_changes/session_changes.dart';
import 'package:maktub_backend/features/sesion/session_changes/session_changes_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

class _FakeStore implements SessionChangesStore {
  final sessions = <String, Session>{};
  final records = <SetRecord>[];
  final athletes = <String, String>{};
  final groups = <String, List<String>>{};

  void seed(String clubId, {int lastSessionChange = 0, String planId = 'p1'}) {
    sessions['$clubId/s1'] = Session(
      id: 's1',
      clubId: clubId,
      assignmentId: 'a1',
      planId: planId,
      cycle: 1,
      week: 1,
      day: 1,
      date: DateTime.utc(2026, 11, 16),
      sequence: 9,
      lastSessionChange: lastSessionChange,
      auditoria: _audit,
    );
  }

  void addRecord(int sequence, {String clubId = 'club-a', int set = 0}) {
    records.add(
      SetRecord(
        id: 'r$sequence',
        clubId: clubId,
        sessionId: 's1',
        athleteId: 'ari',
        exerciseId: 'sq',
        exerciseName: 'Sentadilla',
        blockIndex: 0,
        prescriptionIndex: 0,
        setIndex: set,
        workFactor: 90,
        pctReal: 72,
        sequence: sequence,
        writtenBy: 'coach',
        auditoria: _audit,
      ),
    );
  }

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      sessions['$clubId/$sessionId'];

  @override
  Future<List<SetRecord>> recordsAfter(
    String clubId,
    String sessionId,
    int since,
  ) async => [
    for (final r in records)
      if (r.clubId == clubId && r.sessionId == sessionId && r.sequence! > since)
        r,
  ];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  Future<String?> groupIdOfAssignment(
    String clubId,
    String assignmentId,
  ) async => sessions.containsKey('$clubId/s1') ? 'g1' : null;

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      groups['$clubId/$groupId'] ?? const [];
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

Future<Response> _get(
  _FakeStore store, {
  String query = 'desde=0',
  ClubContext? club,
}) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x?$query')));
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()((c) => sessionChangesEndpoint(c, 's1', store: store))(
    context,
  );
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

List<Object?> _sequences(Map<String, dynamic> body) => [
  for (final c in body['cambios'] as List) (c as Map)['secuencia'],
];

void main() {
  test('gives exactly what came after the number, in order', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..addRecord(4, set: 2)
      ..addRecord(2, set: 0)
      ..addRecord(3, set: 1);

    final body = await _json(await _get(store, query: 'desde=2'));

    expect(_sequences(body), [3, 4]);
    expect(body['secuencia'], 9);
  });

  test('from zero it gives everything, up to date it gives nothing', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..addRecord(1)
      ..addRecord(2, set: 1);

    expect(_sequences(await _json(await _get(store))), [1, 2]);
    expect(
      _sequences(await _json(await _get(store, query: 'desde=2'))),
      isEmpty,
    );
  });

  test('a change of the session comes in its place, parsed', () async {
    final store = _FakeStore()
      ..seed('club-a', lastSessionChange: 3)
      ..addRecord(2)
      ..addRecord(4, set: 1);

    final body = await _json(await _get(store, query: 'desde=1'));

    expect(_sequences(body), [2, 3, 4]);
    final change = SessionChange.fromJson(
      (body['cambios'] as List)[1] as Map<String, dynamic>,
    );
    expect(change.session!.id, 's1');
  });

  test('a session change already seen does not come again', () async {
    final store = _FakeStore()..seed('club-a', lastSessionChange: 3);

    expect(
      _sequences(await _json(await _get(store, query: 'desde=3'))),
      isEmpty,
    );
  });

  test('an athlete of the group does not get the factor', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..addRecord(1)
      ..athletes['club-a/user-ari'] = 'ari'
      ..groups['club-a/g1'] = const ['ari'];

    final response = await _get(store, club: _athlete());

    final change = ((await _json(response))['cambios'] as List).single as Map;
    expect(change['registro'], isNot(contains('factor')));
    expect(change['registro'], isNot(contains('pctReal')));
  });

  test('the coach gets it', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..addRecord(1);

    final change = ((await _json(await _get(store)))['cambios'] as List).single;

    expect((change as Map)['registro']['factor'], 90);
  });

  test('an athlete outside the group does not find the session', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..athletes['club-a/user-ari'] = 'ari'
      ..groups['club-a/g1'] = const ['andi'];

    final response = await _get(store, club: _athlete());

    expect(response.statusCode, HttpStatus.notFound);
  });

  test('records of another club never come', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..addRecord(1, clubId: 'club-b');

    expect(_sequences(await _json(await _get(store))), isEmpty);
  });

  test('a session of another club is not found', () async {
    final store = _FakeStore()..seed('club-b');

    expect((await _get(store)).statusCode, HttpStatus.notFound);
  });

  for (final query in ['', 'desde=', 'desde=-1', 'desde=dos']) {
    test('"$query" is a bad request', () async {
      final store = _FakeStore()..seed('club-a');

      expect(
        (await _get(store, query: query)).statusCode,
        HttpStatus.badRequest,
      );
    });
  }

  final isolated = _FakeStore();
  testClubIsolation(
    'GET /clubes/{clubId}/sesiones/{sesionId}/cambios',
    endpoint: (context) =>
        sessionChangesEndpoint(context, 's1', store: isolated),
    path: '/clubes/{clubId}/sesiones/s1/cambios?desde=0',
    action: Accion.registrar,
    seed: (clubId, marker) {
      isolated.seed(clubId, lastSessionChange: 1, planId: marker);
    },
  );
}
