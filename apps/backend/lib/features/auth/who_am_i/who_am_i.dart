import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'who_am_i_store.dart';

/// `GET /me` (needs `requireUser`) → `{usuario, clubPersonal, clubes: [{club, roles, atletaId}], esAdminPlataforma}`.
Future<Response> whoAmIEndpoint(RequestContext context) async {
  final me = await WhoAmI(MongoWhoAmIStore(context.read<Db>()))(context.read<CurrentUser>().userId);
  return Response.json(body: me.toJson());
}

class ClubAccess {
  const ClubAccess({required this.club, required this.roles, this.atletaId});

  final Club club;
  final Set<Rol> roles;

  /// The user's `Atleta` id in this club, or null if they have none.
  final String? atletaId;

  Json toJson() => {'club': club.toJson(), 'roles': rolesACable(roles), 'atletaId': atletaId};
}

class Me {
  const Me({required this.user, required this.personalClub, required this.clubs});

  final Usuario user;
  final Club? personalClub;

  /// One entry per active membership. Ended memberships never appear.
  final List<ClubAccess> clubs;

  Json toJson() => {
        'usuario': user.toJson(),
        'clubPersonal': personalClub?.toJson(),
        'clubes': [for (final c in clubs) c.toJson()],
        'esAdminPlataforma': user.esAdminPlataforma,
      };
}

/// Who the authenticated user is and what they can access. The app calls it after login and on start.
class WhoAmI {
  WhoAmI(this._store);

  final WhoAmIStore _store;

  Future<Me> call(String userId) async {
    final user = await _store.findUser(userId);
    // A valid token for a user that no longer exists is no longer a session.
    if (user == null) throw const ErrorDeSolicitud('Necesitás iniciar sesión.', estado: HttpStatus.unauthorized);

    final memberships = (await _store.activeMemberships(userId)).where((m) => m.activa).toList();
    final clubIds = {...memberships.map((m) => m.clubId), user.clubPersonalId};
    final byId = {for (final c in await _store.clubsByIds(clubIds)) c.id: c};
    final athleteIds = await _store.athleteIdsByClub(userId, {for (final m in memberships) m.clubId});

    return Me(
      user: user,
      personalClub: byId[user.clubPersonalId],
      clubs: [
        for (final m in memberships)
          if (byId[m.clubId] != null) ClubAccess(club: byId[m.clubId]!, roles: m.roles, atletaId: athleteIds[m.clubId]),
      ]..sort((a, b) => a.club.nombre.compareTo(b.club.nombre)),
    );
  }
}
