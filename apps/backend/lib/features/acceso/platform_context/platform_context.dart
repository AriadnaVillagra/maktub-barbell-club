import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'platform_context_store.dart';

/// Who acts on platform data (`/plataforma/…`): the user and whether they are a platform admin. It grants
/// nothing inside a club: club routes go through `ClubContext` and the membership.
class PlatformContext {
  const PlatformContext({required this.userId, required this.isPlatformAdmin});

  final String userId;
  final bool isPlatformAdmin;

  bool can(Accion action) => canOnPlatform(action, isPlatformAdmin: isPlatformAdmin);

  /// Throws a 403 unless [can] allows [action]. Each slice calls it first.
  PlatformContext authorize(Accion action) {
    if (!can(action)) throw notAPlatformAdmin;
    return this;
  }
}

// 403, never 401: the app treats 401 as "renew the token and retry".
const notAPlatformAdmin = ErrorDeSolicitud(
  'Solo un administrador de plataforma puede hacer esto.',
  estado: HttpStatus.forbidden,
);

/// Goes in `routes/plataforma/_middleware.dart`, inside [requireUser]: reads the platform admin flag from
/// the user's document (never from the token, so taking the flag away works at once) and provides
/// [PlatformContext] to every handler below. [store] is for tests.
Middleware requirePlatform({PlatformContextStore Function(RequestContext context)? store}) =>
    (handler) => (context) async {
      final userId = context.read<CurrentUser>().userId;
      final source = store?.call(context) ?? MongoPlatformContextStore(context.read<Db>());
      final platform = PlatformContext(userId: userId, isPlatformAdmin: await source.isPlatformAdmin(userId));
      return handler(context.provide<PlatformContext>(() => platform));
    };
