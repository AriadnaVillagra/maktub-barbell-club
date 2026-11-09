import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/set_session_note/set_session_note.dart';
import 'package:maktub_backend/features/sesion/set_session_note/set_session_note_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

class _FakeStore implements SetSessionNoteStore {
  final sessions = <String, Session>{};
  final athletes = <String, String>{};

  void seed(
    String clubId, {
    List<String> present = const ['ari'],
    String? note,
  }) {
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
      note: note,
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
  Future<Session> setNote(
    String clubId,
    String sessionId,
    String? note, {
    required String userId,
    required DateTime at,
  }) async {
    final old = sessions['$clubId/$sessionId']!;
    return sessions['$clubId/$sessionId'] = Session.fromJson({
      ...old.toJson(),
      'nota': note,
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

Future<Response> _put(
  _FakeStore store,
  Object? body, {
  ClubContext? club,
  String sessionId = 's1',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'PUT',
      Uri.parse('http://localhost/clubes/club-a/sesiones/$sessionId/nota'),
      body: jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => setSessionNoteEndpoint(c, sessionId, store: store),
  )(context);
}

void main() {
  test('a coach writes the note', () async {
    final store = _FakeStore()..seed('club-a');

    final response = await _put(store, {'nota': ' Buen día '});

    expect(response.statusCode, HttpStatus.ok);
    expect(store.sessions['club-a/s1']!.note, 'Buen día');
    expect((await response.json() as Map)['nota'], 'Buen día');
  });

  test('an empty note clears it', () async {
    final store = _FakeStore()..seed('club-a', note: 'Buen día');

    await _put(store, {'nota': ''});

    expect(store.sessions['club-a/s1']!.note, isNull);
  });

  test('a present athlete can write it', () async {
    final store = _FakeStore()
      ..seed('club-a')
      ..athletes['club-a/user-ari'] = 'ari';

    final response = await _put(store, {'nota': 'Hola'}, club: _athlete());

    expect(response.statusCode, HttpStatus.ok);
  });

  test('an athlete who is not present cannot', () async {
    final store = _FakeStore()
      ..seed('club-a', present: const ['andi'])
      ..athletes['club-a/user-ari'] = 'ari';

    final response = await _put(store, {'nota': 'Hola'}, club: _athlete());

    expect(response.statusCode, HttpStatus.forbidden);
    expect(store.sessions['club-a/s1']!.note, isNull);
  });

  test('a session of another club is not found', () async {
    final store = _FakeStore()..seed('club-b');

    final response = await _put(store, {'nota': 'Hola'});

    expect(response.statusCode, HttpStatus.notFound);
    expect(store.sessions['club-b/s1']!.note, isNull);
  });

  for (final (name, body) in [
    ('without a note', <String, dynamic>{}),
    ('with a note that is not text', {'nota': 5}),
    ('with a note too long', {'nota': 'x' * (maxNoteLength + 1)}),
  ]) {
    test('$name is a bad request', () async {
      final store = _FakeStore()..seed('club-a');

      final response = await _put(store, body);

      expect(response.statusCode, HttpStatus.badRequest);
    });
  }

  final isolated = _FakeStore();
  testClubIsolation(
    'PUT /clubes/{clubId}/sesiones/{sesionId}/nota',
    endpoint: (context) =>
        setSessionNoteEndpoint(context, 's1', store: isolated),
    path: '/clubes/{clubId}/sesiones/s1/nota',
    action: Accion.registrar,
    method: 'PUT',
    body: jsonEncode({'nota': 'x'}),
    seed: (clubId, marker) {
      isolated.seed(clubId, present: [marker]);
    },
  );
}
