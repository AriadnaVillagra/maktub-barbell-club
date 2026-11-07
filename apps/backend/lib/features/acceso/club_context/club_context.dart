import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'club_context_store.dart';

/// The club a request acts in (D7: `/clubes/{clubId}/…`) and what the user is in it.
/// Every slice under that route reads it and filters each query by [clubId].
class ClubContext {
  const ClubContext({required this.clubId, required this.userId, required this.roles, required this.clubType});

  final String clubId;
  final String userId;

  /// Roles of the active membership. Never empty.
  final Set<Rol> roles;
  final TipoClub clubType;

  /// Whether the permission matrix (F1) lets this membership do [action].
  bool can(Accion action) => puede(roles, action, clubType);

  /// Throws a 403 unless [can] allows [action]. Slices call it first when each HTTP method needs a
  /// different action; a route group whose methods all need the same one uses [requireAction].
  ClubContext authorize(Accion action) {
    if (!can(action)) throw forbiddenRole;
    return this;
  }
}

// Both are 403, never 401: the app treats 401 as "renew the token and retry".
const notAMember = ErrorDeSolicitud('No tenés acceso a este club.', estado: HttpStatus.forbidden);
const forbiddenRole = ErrorDeSolicitud('Tu rol en este club no permite esta acción.', estado: HttpStatus.forbidden);

/// Resolves [ClubContext] from the user's active membership. An ended membership gives no access.
class ResolveClubContext {
  ResolveClubContext(this._store);

  final ClubContextStore _store;

  Future<ClubContext> call({required String userId, required String clubId}) async {
    final membership = await _store.activeMembership(clubId: clubId, userId: userId);
    if (membership == null || !membership.activa || membership.clubId != clubId || membership.roles.isEmpty) {
      throw notAMember;
    }
    final type = await _store.clubType(clubId);
    if (type == null) throw notAMember;
    return ClubContext(clubId: clubId, userId: userId, roles: membership.roles, clubType: type);
  }
}

/// The `{clubId}` segment that follows `clubes` in the request path, or null.
String? clubIdFromPath(Uri uri) {
  final segments = uri.pathSegments;
  final i = segments.indexOf('clubes');
  if (i < 0 || i + 1 >= segments.length || segments[i + 1].isEmpty) return null;
  return segments[i + 1];
}

/// Goes in `routes/clubes/[clubId]/_middleware.dart`, inside [requireUser]: checks the active
/// membership in the club of the path and provides [ClubContext] to every handler below.
/// [store] is for tests; by default it reads Mongo through the provided [Db].
Middleware requireClub({ClubContextStore Function(RequestContext context)? store}) => (handler) => (context) async {
      final clubId = clubIdFromPath(context.request.uri);
      if (clubId == null) throw const ErrorDeSolicitud.noEncontrado('Club no encontrado.');
      final resolve = ResolveClubContext(store?.call(context) ?? MongoClubContextStore(context.read<Db>()));
      final club = await resolve(userId: context.read<CurrentUser>().userId, clubId: clubId);
      return handler(context.provide<ClubContext>(() => club));
    };

/// For a route group whose handlers all need the same [action]. Goes inside [requireClub].
Middleware requireAction(Accion action) => (handler) => (context) {
      context.read<ClubContext>().authorize(action);
      return handler(context);
    };
