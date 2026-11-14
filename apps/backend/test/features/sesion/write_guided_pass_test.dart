import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/write_guided_pass/write_guided_pass.dart';
import 'package:maktub_backend/features/sesion/write_guided_pass/write_guided_pass_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));
final _t0 = DateTime.utc(2026, 11, 14, 10);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

class _FakeStore implements WriteGuidedPassStore {
  final sessions = <String, Session>{};
  final athletes = <String, String>{};
  int sequence = 0;
  int writes = 0;

  /// Each read waits a turn, so two writes sent together really overlap unless the slice serializes them.
  bool slow = false;

  void seed(String clubId, {List<String> present = const ['ari']}) {
    sessions['$clubId/s1'] = Session(
      id: 's1',
      clubId: clubId,
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 1,
      week: 1,
      day: 1,
      date: DateTime.utc(2026, 11, 16),
      presentAthleteIds: present,
      auditoria: _audit,
    );
  }

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    if (slow) await Future<void>.delayed(Duration.zero);
    return sessions['$clubId/$sessionId'];
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  Future<int> nextSequence(String clubId, String sessionId) async => ++sequence;

  @override
  Future<Session> setPass(
    String clubId,
    String sessionId,
    GuidedPass pass, {
    required int sequence,
    required String userId,
    required DateTime at,
  }) async {
    if (slow) await Future<void>.delayed(Duration.zero);
    writes++;
    final old = sessions['$clubId/$sessionId']!;
    return sessions['$clubId/$sessionId'] = Session.fromJson({
      ...old.toJson(),
      'pasadaGuiada': pass.toJson(),
      'secuencia': sequence,
      'secuenciaSesion': sequence,
    });
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

Json _begin({String id = 'p1', String? replaces, int version = 0}) =>
    GuidedPassAction.begin(
      passId: id,
      version: version,
      at: _t0,
      replaces: replaces,
      athleteIds: const ['ari'],
      blocks: const [
        GuidedBlockStart(
          athleteMode: AthleteMode.simultaneous,
          executionMode: ExecutionMode.sequential,
        ),
        GuidedBlockStart(
          athleteMode: AthleteMode.simultaneous,
          executionMode: ExecutionMode.sequential,
        ),
      ],
    ).toJson();

Json _on(GuidedActionKind kind, int block, {int minute = 1, int version = 1}) =>
    GuidedPassAction.onBlock(
      kind,
      passId: 'p1',
      version: version,
      at: _at(minute),
      block: block,
    ).toJson();

Future<Response> _post(
  _FakeStore store,
  Object? body, {
  ClubContext? club,
  LiveBroadcast? broadcast,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost/clubes/club-a/sesiones/s1/pasada'),
      body: jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => writeGuidedPassEndpoint(
      c,
      's1',
      store: store,
      broadcast: broadcast ?? MemoryLiveBroadcast(),
    ),
  )(context);
}

GuidedPass _pass(_FakeStore store, [String clubId = 'club-a']) =>
    store.sessions['$clubId/s1']!.guidedPass!;

void main() {
  test('a coach begins the pass and gets the session with it', () async {
    final store = _FakeStore()..seed('club-a');

    final response = await _post(store, _begin());

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.json() as Map;
    expect((body['pasadaGuiada'] as Map)['id'], 'p1');
    expect((body['pasadaGuiada'] as Map)['atletaIds'], ['ari']);
    expect(_pass(store).version, 1);
  });

  test('every change is published as a change of the session', () async {
    final store = _FakeStore()..seed('club-a');
    final broadcast = MemoryLiveBroadcast();
    final seen = <SessionChange>[];
    broadcast.changesOf('club-a', 's1').listen(seen.add);

    await _post(store, _begin(), broadcast: broadcast);
    await _post(
      store,
      _on(GuidedActionKind.startBlock, 0),
      broadcast: broadcast,
    );
    await pumpEventQueue();

    expect(seen.map((c) => c.sequence), [1, 2]);
    expect(
      seen.last.session!.guidedPass!.blocks[0].status,
      GuidedBlockStatus.running,
    );
  });

  test('a write that changes nothing is not a change', () async {
    final store = _FakeStore()..seed('club-a');
    final broadcast = MemoryLiveBroadcast();
    await _post(store, _begin(), broadcast: broadcast);
    await _post(
      store,
      _on(GuidedActionKind.skipBlock, 0),
      broadcast: broadcast,
    );
    final seen = <SessionChange>[];
    broadcast.changesOf('club-a', 's1').listen(seen.add);

    final response = await _post(
      store,
      _on(GuidedActionKind.skipBlock, 0),
      broadcast: broadcast,
    );
    await pumpEventQueue();

    expect(response.statusCode, HttpStatus.ok);
    expect(seen, isEmpty);
    expect(store.sequence, 2);
    expect(_pass(store).current, 1);
  });

  test('two devices finishing the same block at once: it closes once, with the first end', () async {
    final store = _FakeStore()..seed('club-a');
    final broadcast = MemoryLiveBroadcast();
    await _post(store, _begin(), broadcast: broadcast);
    await _post(
      store,
      _on(GuidedActionKind.startBlock, 0),
      broadcast: broadcast,
    );
    store.slow = true;
    final writes = store.writes;

    final responses = await Future.wait([
      _post(
        store,
        _on(GuidedActionKind.finishBlock, 0, minute: 3, version: 2),
        broadcast: broadcast,
      ),
      _post(
        store,
        _on(GuidedActionKind.finishBlock, 0, minute: 4, version: 2),
        broadcast: broadcast,
      ),
    ]);

    expect(responses.map((r) => r.statusCode), [HttpStatus.ok, HttpStatus.ok]);
    expect(store.writes - writes, 1);
    expect(_pass(store).blocks[0].status, GuidedBlockStatus.done);
    expect(_pass(store).blocks[0].end, _at(3));
    expect(_pass(store).current, 1);
  });

  test('two writes at once on a stale version are both applied over the newest pass', () async {
    final store = _FakeStore()..seed('club-a');
    final broadcast = MemoryLiveBroadcast();
    await _post(store, _begin(), broadcast: broadcast);
    await _post(
      store,
      _on(GuidedActionKind.startBlock, 0),
      broadcast: broadcast,
    );
    store.slow = true;

    Json passed(String athlete) => GuidedPassAction.passSets(
      passId: 'p1',
      version: 2,
      at: _at(2),
      block: 0,
      sets: {AthleteSet(athlete, 0, 0)},
    ).toJson();
    await Future.wait([
      _post(store, passed('ari'), broadcast: broadcast),
      _post(store, passed('andi'), broadcast: broadcast),
    ]);

    expect(_pass(store).blocks[0].passed, {
      const AthleteSet('ari', 0, 0),
      const AthleteSet('andi', 0, 0),
    });
    expect(_pass(store).version, 4);
  });

  test(
    'two "Comenzar" at once leave one pass: the second joins the first',
    () async {
      final store = _FakeStore()..seed('club-a');
      store.slow = true;

      final broadcast = MemoryLiveBroadcast();
      await Future.wait([
        _post(store, _begin(id: 'a'), broadcast: broadcast),
        _post(store, _begin(id: 'b'), broadcast: broadcast),
      ]);

      expect(['a', 'b'], contains(_pass(store).id));
      expect(store.writes, 1);
    },
  );

  test('a new pass replaces the one the device saw', () async {
    final store = _FakeStore()..seed('club-a');
    await _post(store, _begin(id: 'a'));

    await _post(store, _begin(id: 'b', replaces: 'a', version: 1));

    expect(_pass(store).id, 'b');
  });

  test('a present athlete can write it', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..athletes['club-a/user-ari'] = 'ari';

    final response = await _post(store, _begin(), club: _athlete());

    expect(response.statusCode, HttpStatus.ok);
  });

  test('an athlete who is not present cannot', () async {
    final store = _FakeStore()
      ..seed('club-a', present: const ['andi'])
      ..athletes['club-a/user-ari'] = 'ari';

    final response = await _post(store, _begin(), club: _athlete());

    expect(response.statusCode, HttpStatus.forbidden);
    expect(store.sessions['club-a/s1']!.guidedPass, isNull);
  });

  test('a session of another club is not found', () async {
    final store = _FakeStore()..seed('club-b');

    final response = await _post(store, _begin());

    expect(response.statusCode, HttpStatus.notFound);
    expect(store.sessions['club-b/s1']!.guidedPass, isNull);
  });

  for (final (name, body) in [
    ('without a kind', <String, dynamic>{..._begin()}..remove('tipo')),
    ('with an unknown kind', {..._begin(), 'tipo': 'volar'}),
    ('with a bad pass id', {..._begin(), 'pasadaId': 'a b'}),
    ('without athletes', {..._begin(), 'atletaIds': <String>[]}),
    (
      'with a bad block',
      {..._on(GuidedActionKind.startBlock, 0), 'bloque': 'x'},
    ),
    ('with a bad instant', {..._begin(), 'en': 'ayer'}),
  ]) {
    test('$name is a bad request', () async {
      final store = _FakeStore()..seed('club-a');

      final response = await _post(store, body);

      expect(response.statusCode, HttpStatus.badRequest);
    });
  }

  final isolated = _FakeStore();
  testClubIsolation(
    'POST /clubes/{clubId}/sesiones/{sesionId}/pasada',
    endpoint: (context) => writeGuidedPassEndpoint(
      context,
      's1',
      store: isolated,
      broadcast: MemoryLiveBroadcast(),
    ),
    path: '/clubes/{clubId}/sesiones/s1/pasada',
    action: Accion.registrar,
    method: 'POST',
    body: jsonEncode(_begin()),
    seed: (clubId, marker) {
      isolated.seed(clubId, present: [marker]);
    },
  );
}
