import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/block_times/block_times.dart';
import 'package:maktub_backend/features/sesion/block_times/block_times_store.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

/// One fake for both slices: the same data, read and written through each slice's own interface.
class _FakeStore implements RecordBlockTimeStore, BlockTimesStore {
  final sessions = <String, Session>{};
  final athletes = <String, String>{};
  final times = <String, BlockTime>{};

  /// Per club, a name the fake stamps on what it stores, so an isolation check can see the response is that club's.
  final stamp = <String, String>{};

  void seed(String clubId, {List<String> present = const ['ari', 'andi']}) {
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

  void seedTime(String clubId, String id, {String name = 'Fuerza'}) {
    times['$clubId/s1/$id'] = BlockTime(
      id: id,
      clubId: clubId,
      sessionId: 's1',
      blockIndex: 0,
      blockName: name,
      athleteIds: const ['ari'],
      start: DateTime.utc(2026, 11, 16, 18),
      end: DateTime.utc(2026, 11, 16, 18, 10),
      auditoria: _audit,
    );
  }

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      sessions['$clubId/$sessionId'];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  Future<BlockTime> upsert(BlockTime time) async {
    final name = stamp[time.clubId];
    if (name != null) {
      time = BlockTime.fromJson({...time.toJson(), 'bloqueNombre': name});
    }
    final key = '${time.clubId}/${time.sessionId}/${time.id}';
    final old = times[key];
    return times[key] = old == null
        ? time
        : BlockTime.fromJson({
            ...time.toJson(),
            'auditoria': {
              ...time.auditoria.toJson(),
              'creadoPor': old.auditoria.creadoPor,
              'creadoEn': old.auditoria.creadoEn.toIso8601String(),
            },
          });
  }

  @override
  Future<List<BlockTime>> timesOf(String clubId, String sessionId) async => [
    for (final t in times.values)
      if (t.clubId == clubId && t.sessionId == sessionId) t,
  ]..sort((a, b) => a.start.compareTo(b.start));
}

ClubContext _athlete({TipoClub type = TipoClub.club}) => ClubContext(
  clubId: 'club-a',
  userId: 'user-ari',
  roles: const {Rol.atleta},
  clubType: type,
);

ClubContext _coach() => const ClubContext(
  clubId: 'club-a',
  userId: 'coach',
  roles: {Rol.coach},
  clubType: TipoClub.club,
);

Map<String, dynamic> _body({
  List<String> athletes = const ['ari'],
  Object? start = '2026-11-16T18:00:00Z',
  Object? end = '2026-11-16T18:12:30Z',
  Object? mode = 'por_turnos',
}) => {
  'bloque': 1,
  'bloqueNombre': 'Fuerza',
  'modoAtletas': ?mode,
  'atletaIds': athletes,
  'inicio': start,
  'fin': end,
  'interrumpido': true,
};

Future<Response> _put(
  _FakeStore store,
  Object? body, {
  ClubContext? club,
  String timeId = 't1',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'PUT',
      Uri.parse('http://localhost/clubes/club-a/sesiones/s1/tiempos/$timeId'),
      body: jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => recordBlockTimeEndpoint(
      c,
      's1',
      timeId,
      store: store,
      now: () => DateTime.utc(2026, 11, 16, 19),
    ),
  )(context);
}

Future<Response> _get(_FakeStore store, {ClubContext? club}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'GET',
      Uri.parse('http://localhost/clubes/club-a/sesiones/s1/tiempos'),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()((c) => blockTimesEndpoint(c, 's1', store: store))(
    context,
  );
}

void main() {
  group('PUT tiempos/{tiempoId}', () {
    test('stores the time and answers with it, seconds derived', () async {
      final store = _FakeStore()..seed('club-a');

      final response = await _put(store, _body());

      expect(response.statusCode, HttpStatus.ok);
      final json = await response.json() as Map;
      expect(json['id'], 't1');
      expect(json['modoAtletas'], 'por_turnos');
      expect(json['interrumpido'], true);
      expect(json.containsKey('segundos'), isFalse);
      final stored = store.times['club-a/s1/t1']!;
      expect(stored.seconds, 750);
      expect(stored.blockName, 'Fuerza');
      expect(stored.auditoria.creadoPor, 'coach');
    });

    test('repeating the same PUT leaves one document', () async {
      final store = _FakeStore()..seed('club-a');

      await _put(store, _body());
      final again = await _put(store, _body());

      expect(again.statusCode, HttpStatus.ok);
      expect(store.times, hasLength(1));
    });

    test('a block done twice leaves two times', () async {
      final store = _FakeStore()..seed('club-a');

      await _put(store, _body(), timeId: 't1');
      await _put(
        store,
        _body(start: '2026-11-16T18:30:00Z', end: '2026-11-16T18:40:00Z'),
        timeId: 't2',
      );

      expect(store.times, hasLength(2));
      expect(store.times.values.map((t) => t.blockIndex), [1, 1]);
    });

    test('a block without sets has no athlete mode', () async {
      final store = _FakeStore()..seed('club-a');

      await _put(store, _body(mode: null));

      expect(store.times['club-a/s1/t1']!.athleteMode, isNull);
    });

    test('a present athlete writes for present athletes', () async {
      final store = _FakeStore()
        ..seed('club-a')
        ..athletes['club-a/user-ari'] = 'ari';

      final response = await _put(
        store,
        _body(athletes: const ['ari', 'andi']),
        club: _athlete(),
      );

      expect(response.statusCode, HttpStatus.ok);
    });

    test('an athlete not present cannot', () async {
      final store = _FakeStore()
        ..seed('club-a', present: const ['andi'])
        ..athletes['club-a/user-ari'] = 'ari';

      final response = await _put(
        store,
        _body(athletes: const ['andi']),
        club: _athlete(),
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(store.times, isEmpty);
    });

    test('in a personal club an athlete writes only for themselves', () async {
      final store = _FakeStore()
        ..seed('club-a')
        ..athletes['club-a/user-ari'] = 'ari';

      final response = await _put(
        store,
        _body(athletes: const ['andi']),
        club: _athlete(type: TipoClub.personal),
      );

      expect(response.statusCode, HttpStatus.forbidden);
    });

    test(
      'an athlete who is not present in the session is unprocessable',
      () async {
        final store = _FakeStore()..seed('club-a', present: const ['ari']);

        final response = await _put(store, _body(athletes: const ['zoe']));

        expect(response.statusCode, HttpStatus.unprocessableEntity);
        expect(store.times, isEmpty);
      },
    );

    test('a session of another club is not found', () async {
      final store = _FakeStore()..seed('club-b');

      final response = await _put(store, _body());

      expect(response.statusCode, HttpStatus.notFound);
      expect(store.times, isEmpty);
    });

    for (final (name, body) in [
      ('an end before the start', _body(end: '2026-11-16T17:00:00Z')),
      ('an instant that is not a date', _body(start: 'ayer')),
      ('no athletes', _body(athletes: const [])),
      ('an unknown athlete mode', _body(mode: 'lento')),
    ]) {
      test('$name is a bad request', () async {
        final store = _FakeStore()..seed('club-a');

        final response = await _put(store, body);

        expect(response.statusCode, HttpStatus.badRequest);
        expect(store.times, isEmpty);
      });
    }

    test('an id with odd characters is a bad request', () async {
      final store = _FakeStore()..seed('club-a');

      final response = await _put(store, _body(), timeId: 'a b');

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('GET tiempos', () {
    test('returns the times of the session, oldest first', () async {
      final store = _FakeStore()
        ..seed('club-a')
        ..seedTime('club-a', 't1');
      await _put(
        store,
        _body(start: '2026-11-16T17:00:00Z', end: '2026-11-16T17:05:00Z'),
        timeId: 't0',
      );

      final response = await _get(store);

      final times = (await response.json() as Map)['tiempos'] as List;
      expect(times.map((t) => (t as Map)['id']), ['t0', 't1']);
    });

    test('a present athlete reads them, one who is not does not', () async {
      final store = _FakeStore()
        ..seed('club-a', present: const ['andi'])
        ..seedTime('club-a', 't1')
        ..athletes['club-a/user-ari'] = 'ari';

      final response = await _get(store, club: _athlete());

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('does not return the times of another session or club', () async {
      final store = _FakeStore()
        ..seed('club-a')
        ..seedTime('club-b', 'other');

      final response = await _get(store);

      expect((await response.json() as Map)['tiempos'], isEmpty);
    });
  });

  final writeStore = _FakeStore();
  testClubIsolation(
    'PUT /clubes/{clubId}/sesiones/{sesionId}/tiempos/{tiempoId}',
    endpoint: (context) =>
        recordBlockTimeEndpoint(context, 's1', 't1', store: writeStore),
    path: '/clubes/{clubId}/sesiones/s1/tiempos/t1',
    action: Accion.registrar,
    method: 'PUT',
    body: jsonEncode(_body()),
    seed: (clubId, marker) {
      writeStore
        ..seed(clubId)
        ..stamp[clubId] = marker;
    },
  );

  final readStore = _FakeStore();
  testClubIsolation(
    'GET /clubes/{clubId}/sesiones/{sesionId}/tiempos',
    endpoint: (context) => blockTimesEndpoint(context, 's1', store: readStore),
    path: '/clubes/{clubId}/sesiones/s1/tiempos',
    action: Accion.registrar,
    seed: (clubId, marker) {
      readStore
        ..seed(clubId)
        ..seedTime(clubId, 't1', name: marker);
    },
  );
}
