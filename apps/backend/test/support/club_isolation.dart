import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context_store.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements ClubContextStore {
  final memberships = <Membresia>[];
  final clubs = <String, TipoClub>{};

  @override
  Future<Membresia?> activeMembership({required String clubId, required String userId}) async {
    for (final m in memberships) {
      if (m.clubId == clubId && m.usuarioId == userId && m.activa) return m;
    }
    return null;
  }

  @override
  Future<TipoClub?> clubType(String clubId) async => clubs[clubId];

  @override
  Future<bool> isPlatformAdmin(String userId) async => false;
}

/// Reusable club isolation check (F1 §5, design §3.3) for any endpoint under `/clubes/{clubId}/…`.
///
/// One call to [testClubIsolation] registers three cases against the endpoint, running it behind
/// the real `manejarErrores` + [requireClub] + [requireAction]:
///
/// 1. a user with no membership in the club is rejected (403) and sees none of its data;
/// 2. a member whose roles don't allow [action] is rejected (403) and sees none of its data;
/// 3. a member of two clubs, asking for one, gets data of that club and none of the other.
///
/// Usage from a slice test:
///
/// ```dart
/// testClubIsolation(
///   'GET /clubes/{clubId}/planes',
///   endpoint: (context) => listPlans(context, store),   // the slice endpoint, same handler as in routes/
///   path: '/clubes/{clubId}/planes',
///   action: Accion.ver,                                 // what the route group requires
///   seed: (clubId, marker) => store.add(clubId, name: marker), // put one record in that club with [marker] in it
/// );
/// ```
///
/// [seed] must store data so that a correct endpoint returns [marker] somewhere in the response
/// body when called for [clubId], and never when called for another club. The marker is unique per
/// call (`marker-<clubId>-<n>`), so data left from earlier cases cannot interfere. Build the
/// endpoint over a fake store that lives for the whole `testClubIsolation` call (create it before).
/// For a mutating endpoint (POST/PUT/DELETE) pass [method] and [body]; "data" is then whatever the
/// response echoes, so [seed] should arrange for the response to contain the marker.
void testClubIsolation(
  String description, {
  required Handler endpoint,
  required String path,
  required Accion action,
  required FutureOr<void> Function(String clubId, String marker) seed,
  String method = 'GET',
  Object? body,
  TipoClub clubType = TipoClub.club,
}) {
  final check = ClubIsolationCheck(
    endpoint: endpoint,
    path: path,
    action: action,
    seed: seed,
    method: method,
    body: body,
    clubType: clubType,
  );
  group('club isolation: $description', () {
    test('rejects a user with no membership in the club', check.rejectsNonMember);
    test(
      'rejects a member whose role does not allow the action',
      check.rejectsWrongRole,
      skip: check.rolesWithout(action).isEmpty ? 'every role can do $action in a $clubType' : null,
    );
    test('returns no data of another club', check.hidesOtherClubs);
  });
}

/// The three cases of [testClubIsolation] as plain async functions that throw [TestFailure].
/// Exposed so a test can assert that a leaky endpoint fails them.
class ClubIsolationCheck {
  ClubIsolationCheck({
    required this.endpoint,
    required this.path,
    required this.action,
    required this.seed,
    this.method = 'GET',
    this.body,
    this.clubType = TipoClub.club,
  });

  final Handler endpoint;
  final String path;
  final Accion action;
  final FutureOr<void> Function(String clubId, String marker) seed;
  final String method;
  final Object? body;
  final TipoClub clubType;

  static var _counter = 0;
  static final _now = DateTime.utc(2026, 11, 7, 12);

  /// Role sets (single roles) that [puede] denies [action] in [clubType].
  List<Set<Rol>> rolesWithout(Accion action) =>
      [for (final r in Rol.values) if (!puede({r}, action, clubType)) {r}];

  Set<Rol> get _allowed => {
        for (final r in Rol.values)
          if (puede({r}, action, clubType)) r,
      };

  String _marker(String clubId) => 'marker-$clubId-${_counter++}';

  Membresia _membership(String clubId, Set<Rol> roles, String userId) => Membresia(
        id: 'm-$clubId-$userId',
        clubId: clubId,
        usuarioId: userId,
        roles: roles,
        estado: EstadoMembresia.activa,
        desde: _now,
        auditoria: Auditoria.nueva(userId, ahora: _now),
      );

  /// Runs the endpoint for [userId] at [clubId], with the memberships in [store].
  Future<Response> _call(_FakeStore store, String clubId, String userId) async {
    final context = _Context();
    final uri = Uri.parse('http://localhost${path.replaceAll('{clubId}', clubId)}');
    when(() => context.request).thenReturn(Request(method, uri, body: body == null ? null : '$body'));
    when(() => context.read<CurrentUser>()).thenReturn(CurrentUser(userId: userId, sessionId: 's1'));
    when(() => context.provide<ClubContext>(any())).thenAnswer((inv) {
      final club = (inv.positionalArguments.first as ClubContext Function())();
      final inner = _Context();
      when(() => inner.read<ClubContext>()).thenReturn(club);
      when(() => inner.request).thenReturn(context.request);
      return inner;
    });
    final guarded = requireAction(action)(endpoint);
    return manejarErrores()(requireClub(store: (_) => store)(guarded))(context);
  }

  _FakeStore _store() => _FakeStore()
    ..clubs.addAll({'club-a': clubType, 'club-b': clubType});

  /// Asserts [r] was a 403 that leaks none of [markers].
  Future<void> _expectForbidden(Response r, List<String> markers) async {
    final text = await r.body();
    expect(r.statusCode, HttpStatus.forbidden, reason: 'expected 403, got ${r.statusCode}: $text');
    for (final m in markers) {
      expect(text, isNot(contains(m)), reason: 'a rejected request leaked data of the club');
    }
  }

  /// The user belongs to `club-b` only (with a role that can do the action) and asks for `club-a`.
  Future<void> rejectsNonMember() async {
    final store = _store()..memberships.add(_membership('club-b', _allowed, 'u1'));
    final markerA = _marker('club-a');
    await seed('club-a', markerA);
    await _expectForbidden(await _call(store, 'club-a', 'u1'), [markerA]);
  }

  /// The user is an active member of `club-a`, but only with roles that can't do the action.
  Future<void> rejectsWrongRole() async {
    final denied = rolesWithout(action);
    if (denied.isEmpty) return;
    final store = _store()..memberships.add(_membership('club-a', denied.first, 'u1'));
    final markerA = _marker('club-a');
    await seed('club-a', markerA);
    await _expectForbidden(await _call(store, 'club-a', 'u1'), [markerA]);
  }

  /// The user is a member of both clubs; each club's request returns its own data only.
  Future<void> hidesOtherClubs() async {
    final store = _store()
      ..memberships.addAll([_membership('club-a', _allowed, 'u1'), _membership('club-b', _allowed, 'u1')]);
    final markerA = _marker('club-a');
    final markerB = _marker('club-b');
    await seed('club-a', markerA);
    await seed('club-b', markerB);

    for (final (clubId, own, foreign) in [('club-a', markerA, markerB), ('club-b', markerB, markerA)]) {
      final r = await _call(store, clubId, 'u1');
      final text = await r.body();
      expect(r.statusCode, HttpStatus.ok, reason: 'expected 200 for $clubId, got ${r.statusCode}: $text');
      expect(text, contains(own), reason: 'the response for $clubId does not contain its own data (is seed wired to the endpoint?)');
      expect(text, isNot(contains(foreign)), reason: 'the response for $clubId leaked data of another club');
    }
  }
}
