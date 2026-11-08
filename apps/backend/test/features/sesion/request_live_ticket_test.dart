import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/features/sesion/request_live_ticket/request_live_ticket.dart';
import 'package:maktub_backend/features/sesion/request_live_ticket/request_live_ticket_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements RequestLiveTicketStore {
  final sessions = <String, Session>{};
  final assignmentGroups = <String, String>{};
  final groups = <String, List<String>>{};
  final athletes = <String, String>{};
  final tickets = <String, LiveTicket>{};
  String? lastClubId;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    lastClubId = clubId;
    return sessions['$clubId/$sessionId'];
  }

  @override
  Future<String?> groupIdOfAssignment(
    String clubId,
    String assignmentId,
  ) async => assignmentGroups['$clubId/$assignmentId'];

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      groups['$clubId/$groupId'] ?? const [];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  void saveTicket(String value, LiveTicket ticket, {required DateTime now}) =>
      tickets[value] = ticket;
}

final _now = DateTime.utc(2026, 11, 8, 18);

Session _session(String clubId, {String id = 's1'}) => Session(
  id: id,
  clubId: clubId,
  assignmentId: 'a1',
  planId: 'p1',
  cycle: 1,
  week: 1,
  day: 1,
  date: DateTime.utc(2026, 11, 8),
  auditoria: Auditoria.nueva('coach', ahora: _now),
);

ClubContext _club(
  Set<Rol> roles, {
  String clubId = 'c1',
  String userId = 'u1',
}) => ClubContext(
  clubId: clubId,
  userId: userId,
  roles: roles,
  clubType: TipoClub.club,
);

Future<Response> _call(
  _FakeStore store,
  ClubContext club, {
  String sessionId = 's1',
  Map<String, String> headers = const {},
}) async {
  final context = _Context();
  when(() => context.read<ClubContext>()).thenReturn(club);
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse(
        'http://localhost/clubes/${club.clubId}/sesiones/$sessionId/ticket',
      ),
      headers: headers,
    ),
  );
  return manejarErrores()(
    (c) => requestLiveTicketEndpoint(
      c,
      sessionId,
      store: store,
      newTicket: () => 'the-ticket',
      now: () => _now,
    ),
  )(context);
}

void main() {
  late _FakeStore store;

  setUp(() {
    store = _FakeStore()
      ..sessions['c1/s1'] = _session('c1')
      ..assignmentGroups['c1/a1'] = 'g1'
      ..groups['c1/g1'] = ['ath1'];
  });

  test(
    'gives a coach a ticket bound to the club, the session and the user',
    () async {
      final response = await _call(store, _club({Rol.coach}));

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['ticket'], 'the-ticket');
      expect(body['expiresAt'], _now.add(liveTicketLifetime).toIso8601String());

      final ticket = store.tickets['the-ticket']!;
      expect(ticket.clubId, 'c1');
      expect(ticket.sessionId, 's1');
      expect(ticket.userId, 'u1');
      expect(ticket.expiresAt, _now.add(liveTicketLifetime));
    },
  );

  test('the ticket lives for seconds, not minutes', () {
    expect(liveTicketLifetime, lessThanOrEqualTo(const Duration(seconds: 30)));
  });

  test('an athlete of the group gets a ticket', () async {
    store.athletes['c1/u1'] = 'ath1';

    final response = await _call(store, _club({Rol.atleta}));

    expect(response.statusCode, HttpStatus.ok);
    expect(store.tickets, hasLength(1));
  });

  test('an athlete of another group gets a 404 and no ticket', () async {
    store.athletes['c1/u1'] = 'ath2';

    final response = await _call(store, _club({Rol.atleta}));

    expect(response.statusCode, HttpStatus.notFound);
    expect(store.tickets, isEmpty);
  });

  test('a session that does not exist gets a 404 and no ticket', () async {
    final response = await _call(store, _club({Rol.coach}), sessionId: 'nope');

    expect(response.statusCode, HttpStatus.notFound);
    expect(store.tickets, isEmpty);
  });

  test('a session of another club gets a 404 and no ticket', () async {
    store.sessions['c2/s2'] = _session('c2', id: 's2');

    final response = await _call(store, _club({Rol.coach}), sessionId: 's2');

    expect(response.statusCode, HttpStatus.notFound);
    expect(store.tickets, isEmpty);
  });

  test('the response never carries the access token', () async {
    final response = await _call(
      store,
      _club({Rol.coach}),
      headers: {'Authorization': 'Bearer secret-access-token'},
    );

    expect(await response.body(), isNot(contains('secret-access-token')));
  });

  test(
    'without an injected generator each ticket is random and URL-safe',
    () async {
      final endpoint = RequestLiveTicket(store, now: () => _now);

      final first = await endpoint(_club({Rol.coach}), 's1');
      final second = await endpoint(_club({Rol.coach}), 's1');

      expect(first.value, isNot(second.value));
      expect(first.value, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    },
  );

  final isolationStore = _FakeStore();
  final markers = <String, String>{};
  testClubIsolation(
    'POST /clubes/{clubId}/sesiones/{sesionId}/ticket',
    endpoint: (context) => requestLiveTicketEndpoint(
      context,
      's1',
      store: isolationStore,
      newTicket: () => markers[isolationStore.lastClubId]!,
      now: () => _now,
    ),
    path: '/clubes/{clubId}/sesiones/s1/ticket',
    action: Accion.registrar,
    method: 'POST',
    seed: (clubId, marker) {
      markers[clubId] = marker;
      isolationStore.sessions['$clubId/s1'] = _session(clubId);
      isolationStore.assignmentGroups['$clubId/a1'] = 'g1';
      isolationStore.groups['$clubId/g1'] = ['ath1'];
      isolationStore.athletes['$clubId/u1'] = 'ath1';
    },
  );
}
