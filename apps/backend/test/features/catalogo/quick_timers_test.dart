import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/quick_timers/quick_timers.dart';
import 'package:maktub_backend/features/catalogo/quick_timers/quick_timers_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

/// Choices by (club, user); timers by club. Like Mongo, it only answers for the club it is asked about.
class _FakeStore implements QuickTimersStore {
  final saved = <(String, String), QuickTimers>{};
  final timers = <String, Set<String>>{
    'club-a': {'t1', 't2', 'base-1'},
    'club-b': {'tb'},
  };

  @override
  Future<QuickTimers?> find(String clubId, String userId) async => saved[(clubId, userId)];

  @override
  Future<Set<String>> timerIds(String clubId) async => timers[clubId] ?? const {};

  @override
  Future<void> save(QuickTimers quick) async => saved[(quick.clubId, quick.userId)] = quick;
}

ClubContext _ctx(String userId, {String clubId = 'club-a', Set<Rol> roles = const {Rol.atleta}}) =>
    ClubContext(clubId: clubId, userId: userId, roles: roles, clubType: TipoClub.club);

Future<Response> _call(ClubContext ctx, _FakeStore store, String method, [Object? body]) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(method, Uri.parse('http://localhost/x'), body: body == null ? null : jsonEncode(body)),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(
    (c) => method == 'GET' ? getQuickTimersEndpoint(c, store: store) : saveQuickTimersEndpoint(c, store: store),
  )(context);
}

Future<List<dynamic>> _ids(Response r) async => (jsonDecode(await r.body()) as Map)['temporizadorIds'] as List;

void main() {
  test('empty until the user chooses; then their choice, in order and without repeats', () async {
    final store = _FakeStore();

    expect(await _ids(await _call(_ctx('ari'), store, 'GET')), isEmpty);

    final put = await _call(_ctx('ari'), store, 'PUT', {
      'temporizadorIds': ['t2', 'base-1', 't2'],
    });
    expect(put.statusCode, HttpStatus.ok);
    expect(await _ids(await _call(_ctx('ari'), store, 'GET')), ['t2', 'base-1']);
  });

  test("each user has their own: one's choice is not the other's", () async {
    final store = _FakeStore();
    await _call(_ctx('ari'), store, 'PUT', {
      'temporizadorIds': ['t1'],
    });

    expect(await _ids(await _call(_ctx('andi'), store, 'GET')), isEmpty);
  });

  test("a timer the club cannot use, or another club's, is 400 and nothing is written", () async {
    final store = _FakeStore();
    for (final ids in [
      ['nope'],
      ['tb'],
    ]) {
      final r = await _call(_ctx('ari'), store, 'PUT', {'temporizadorIds': ids});
      expect(r.statusCode, HttpStatus.badRequest, reason: '$ids');
    }
    final malformed = await _call(_ctx('ari'), store, 'PUT', {'temporizadorIds': 't1'});
    expect(malformed.statusCode, HttpStatus.badRequest);
    expect(store.saved, isEmpty);
  });

  test('the same user in another club has a separate choice', () async {
    final store = _FakeStore();
    await _call(_ctx('ari'), store, 'PUT', {
      'temporizadorIds': ['t1'],
    });

    expect(await _ids(await _call(_ctx('ari', clubId: 'club-b'), store, 'GET')), isEmpty);
  });
}
