import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context_store.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/features/club_requests/approve_club_request/approve_club_request.dart';
import 'package:maktub_backend/features/club_requests/list_club_requests/list_club_requests.dart';
import 'package:maktub_backend/features/club_requests/reject_club_request/reject_club_request.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_requests.dart';

class _Context extends Mock implements RequestContext {}

class _Admins implements PlatformContextStore {
  const _Admins(this.ids);

  final Set<String> ids;

  @override
  Future<bool> isPlatformAdmin(String userId) async => ids.contains(userId);
}

/// The `/plataforma/pedidos-club` endpoints behind the real error handling and [requirePlatform], as in
/// `routes/plataforma/_middleware.dart` (the user is already authenticated).
void main() {
  late FakeClubRequests db;

  setUp(() {
    db = FakeClubRequests()
      ..put(
        ClubRequest(
          id: 'r1',
          email: 'lu@example.com',
          requesterName: 'Lu',
          clubName: 'Barra Norte',
          auditoria: Auditoria.nueva('lu@example.com', ahora: DateTime.utc(2026, 11, 21)),
        ),
      );
  });

  Future<Response> call(String userId, String method, String path, Handler endpoint) async {
    final context = _Context();
    final request = Request(method, Uri.parse('http://localhost$path'));
    when(() => context.request).thenReturn(request);
    when(() => context.read<CurrentUser>()).thenReturn(CurrentUser(userId: userId, sessionId: 's1'));
    when(() => context.provide<PlatformContext>(any())).thenAnswer((inv) {
      final platform = (inv.positionalArguments.first as PlatformContext Function())();
      final inner = _Context();
      when(() => inner.read<PlatformContext>()).thenReturn(platform);
      when(() => inner.request).thenReturn(request);
      return inner;
    });
    return await manejarErrores()(requirePlatform(store: (_) => const _Admins({'u-andi'}))(endpoint))(context);
  }

  Handler list() => (c) => listClubRequestsEndpoint(c, store: db);
  Handler approve() => (c) => approveClubRequestEndpoint(c, 'r1', store: db);
  Handler reject() => (c) => rejectClubRequestEndpoint(c, 'r1', store: db);

  test('a user who is not a platform admin gets 403 everywhere and changes nothing', () async {
    for (final (method, path, endpoint) in [
      ('GET', '/plataforma/pedidos-club', list()),
      ('POST', '/plataforma/pedidos-club/r1/aprobar', approve()),
      ('POST', '/plataforma/pedidos-club/r1/rechazar', reject()),
    ]) {
      final response = await call('u-coach', method, path, endpoint);
      final text = await response.body();
      expect(response.statusCode, HttpStatus.forbidden, reason: path);
      expect(text, isNot(contains('lu@example.com')), reason: path);
    }
    expect(db.requests['r1']!.isPending, isTrue);
    expect(db.clubs, isEmpty);
  });

  test('a platform admin lists the pending requests and approves one', () async {
    final listed = await call('u-andi', 'GET', '/plataforma/pedidos-club', list());
    expect(listed.statusCode, HttpStatus.ok);
    final pedidos = (jsonDecode(await listed.body()) as Map)['pedidos'] as List;
    expect([for (final p in pedidos) (p as Map)['id']], ['r1']);
    expect(pedidos.single as Map, isNot(contains('googleSub')));

    final approved = await call('u-andi', 'POST', '/plataforma/pedidos-club/r1/aprobar', approve());
    expect(approved.statusCode, HttpStatus.ok);
    final json = jsonDecode(await approved.body()) as Map;
    expect((json['pedido'] as Map)['estado'], 'aprobado');
    expect((json['club'] as Map)['nombre'], 'Barra Norte');
  });

  test('a platform admin rejects one', () async {
    final rejected = await call('u-andi', 'POST', '/plataforma/pedidos-club/r1/rechazar', reject());
    expect(rejected.statusCode, HttpStatus.ok);
    expect(((jsonDecode(await rejected.body()) as Map)['pedido'] as Map)['estado'], 'rechazado');
  });
}
