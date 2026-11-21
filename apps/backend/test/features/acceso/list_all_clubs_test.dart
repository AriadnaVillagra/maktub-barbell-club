import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/list_all_clubs/list_all_clubs.dart';
import 'package:maktub_backend/features/acceso/list_all_clubs/list_all_clubs_store.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context_store.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

class _Admins implements PlatformContextStore {
  const _Admins(this.ids);

  final Set<String> ids;

  @override
  Future<bool> isPlatformAdmin(String userId) async => ids.contains(userId);
}

class _Clubs implements ListAllClubsStore {
  @override
  Future<List<Club>> clubs() async => [
        for (final (id, name) in [('c1', 'Barra Norte'), ('c2', 'Maktub')])
          Club(id: id, nombre: name, tipo: TipoClub.club, auditoria: Auditoria.nueva('u', ahora: DateTime.utc(2026))),
      ];
}

/// `GET /plataforma/clubes` behind the real error handling and [requirePlatform].
void main() {
  Future<Response> call(String userId) async {
    final context = _Context();
    final request = Request('GET', Uri.parse('http://localhost/plataforma/clubes'));
    when(() => context.request).thenReturn(request);
    when(() => context.read<CurrentUser>()).thenReturn(CurrentUser(userId: userId, sessionId: 's1'));
    when(() => context.provide<PlatformContext>(any())).thenAnswer((inv) {
      final platform = (inv.positionalArguments.first as PlatformContext Function())();
      final inner = _Context();
      when(() => inner.read<PlatformContext>()).thenReturn(platform);
      when(() => inner.request).thenReturn(request);
      return inner;
    });
    Future<Response> endpoint(RequestContext c) => listAllClubsEndpoint(c, store: _Clubs());
    return await manejarErrores()(requirePlatform(store: (_) => const _Admins({'u-andi'}))(endpoint))(context);
  }

  test('a platform admin lists every club', () async {
    final response = await call('u-andi');
    expect(response.statusCode, HttpStatus.ok);
    final clubs = (jsonDecode(await response.body()) as Map)['clubes'] as List;
    expect([for (final c in clubs) (c as Map)['nombre']], ['Barra Norte', 'Maktub']);
  });

  test('anyone else gets 403 and no club', () async {
    final response = await call('u-coach');
    expect(response.statusCode, HttpStatus.forbidden);
    expect(await response.body(), isNot(contains('Barra Norte')));
  });
}
