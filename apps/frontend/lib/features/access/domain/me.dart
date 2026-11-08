import 'package:maktub_core/maktub_core.dart';

/// A club the user belongs to, with the roles they hold in it.
class ClubAccess {
  const ClubAccess({required this.club, required this.roles, this.athleteId});

  final Club club;
  final Set<Rol> roles;

  /// The user's athlete id in this club (`atletaId` on the wire); null if none or an older response.
  final String? athleteId;

  /// Whether this user can do [action] in this club. The rules live in `maktub_core`.
  bool can(Accion action) => puede(roles, action, club.tipo);

  factory ClubAccess.fromJson(Json j) => ClubAccess(
    club: Club.fromJson((j['club'] as Map).cast<String, dynamic>()),
    roles: rolesDeCable(j['roles']),
    athleteId: j['atletaId'] as String?,
  );
}

/// The answer of `GET /me`: who the user is and which clubs they can reach.
class Me {
  const Me({
    required this.user,
    required this.personalClub,
    required this.clubs,
    this.isPlatformAdmin = false,
  });

  final Usuario user;
  final Club? personalClub;
  final List<ClubAccess> clubs;

  /// Can change what every club shares (the default catalog).
  final bool isPlatformAdmin;

  factory Me.fromJson(Json j) => Me(
    user: Usuario.fromJson((j['usuario'] as Map).cast<String, dynamic>()),
    personalClub: j['clubPersonal'] == null
        ? null
        : Club.fromJson((j['clubPersonal'] as Map).cast<String, dynamic>()),
    clubs: [
      for (final c in (j['clubes'] as List? ?? const []))
        ClubAccess.fromJson((c as Map).cast<String, dynamic>()),
    ],
    isPlatformAdmin: j['esAdminPlataforma'] == true,
  );

  /// The club the app works in. There is no selector yet (F1), so the criterion is: the first
  /// club the user joined on purpose (the API lists them by name), and the personal club when
  /// there is none. Null when the user has no access to any club.
  ClubAccess? get activeClub {
    for (final c in clubs) {
      if (!c.club.esPersonal) return c;
    }
    for (final c in clubs) {
      if (c.club.esPersonal) return c;
    }
    final personal = personalClub;
    return personal == null
        ? null
        : ClubAccess(club: personal, roles: const {});
  }

  /// Whether planning is available in the active club (never in the personal one).
  bool get canPlan => activeClub?.can(Accion.planificar) ?? false;

  /// Whether the user can create and change what belongs to the active club.
  bool get canEditClubCatalog => activeClub?.can(Accion.editarCatalogoClub) ?? false;

  /// Whether the user can write athletes' references, factors and fixed weights (coach only).
  bool get canEditReferences => activeClub?.can(Accion.editarReferencias) ?? false;

  bool get canManageMembers => activeClub?.can(Accion.gestionarMiembros) ?? false;

  /// Whether the Preferences tab (catalog, timers, equipment, members) is available.
  bool get canConfigure => canPlan || canEditClubCatalog || canManageMembers;

  /// Whether the user can change [item]: default ones need a platform admin, the club's a club admin.
  bool canWriteCatalog(DelClub item) {
    final active = activeClub;
    if (active == null) return false;
    return puedeEscribirCatalogo(item, active.roles, active.club.tipo, esAdminPlataforma: isPlatformAdmin);
  }
}
