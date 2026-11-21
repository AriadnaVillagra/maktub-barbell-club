import 'package:maktub_core/maktub_core.dart';

/// A club the user belongs to, with the roles they hold in it.
class ClubAccess {
  const ClubAccess({required this.club, required this.roles, this.athleteId, this.isPlatformAdmin = false});

  final Club club;

  /// Empty in a club a platform admin entered without being a member.
  final Set<Rol> roles;

  /// The user's athlete id in this club (`atletaId` on the wire); null if none or an older response.
  final String? athleteId;

  /// Whether the user is a platform admin, who can do everything in any club. Not on the wire: [Me.activeClub] sets
  /// it from `esAdminPlataforma`.
  final bool isPlatformAdmin;

  /// Whether this user can do [action] in this club. The rules live in `maktub_core`.
  bool can(Accion action) => puede(roles, action, club.tipo, esAdminPlataforma: isPlatformAdmin);

  ClubAccess _asPlatformAdmin(bool value) => value == isPlatformAdmin
      ? this
      : ClubAccess(club: club, roles: roles, athleteId: athleteId, isPlatformAdmin: value);

  factory ClubAccess.fromJson(Json j) => ClubAccess(
    club: Club.fromJson((j['club'] as Map).cast<String, dynamic>()),
    roles: rolesDeCable(j['roles']),
    athleteId: j['atletaId'] as String?,
  );

  Json toJson() => {
    'club': club.toJson(),
    'roles': [for (final r in roles) r.cable],
    'atletaId': ?athleteId,
  };
}

/// The answer of `GET /me`: who the user is and which clubs they can reach.
class Me {
  const Me({
    required this.user,
    required this.personalClub,
    required this.clubs,
    this.isPlatformAdmin = false,
    this.chosenClub,
  });

  final Usuario user;
  final Club? personalClub;
  final List<ClubAccess> clubs;

  /// Can do everything in any club, even without a membership (support), and change what every club shares (the
  /// default catalog).
  final bool isPlatformAdmin;

  /// The club the user picked to work in, kept on the device and not part of `GET /me` ([withChosenClub]).
  final Club? chosenClub;

  /// The same answer working in [club]: one of the user's clubs, or any club for a platform admin. A club the user
  /// cannot reach anymore is ignored, and null goes back to the default ([activeClub]).
  Me withChosenClub(Club? club) =>
      Me(user: user, personalClub: personalClub, clubs: clubs, isPlatformAdmin: isPlatformAdmin, chosenClub: club);

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

  /// The same shape as `GET /me`, for the device's copy (E7.15).
  Json toJson() => {
    'usuario': user.toJson(),
    'clubPersonal': ?personalClub?.toJson(),
    'clubes': [for (final c in clubs) c.toJson()],
    'esAdminPlataforma': isPlatformAdmin,
  };

  /// The club the app works in: the one picked ([chosenClub]) when the user can still reach it; otherwise the first
  /// club the user joined on purpose (the API lists them by name), and the personal club when there is none. Null
  /// when the user has no access to any club.
  ClubAccess? get activeClub => _defaultOrChosen()?._asPlatformAdmin(isPlatformAdmin);

  ClubAccess? _defaultOrChosen() {
    final chosen = chosenClub;
    if (chosen != null) {
      for (final c in clubs) {
        if (c.club.id == chosen.id) return c;
      }
      if (isPlatformAdmin) return ClubAccess(club: chosen, roles: const {});
    }
    for (final c in clubs) {
      if (!c.club.esPersonal) return c;
    }
    for (final c in clubs) {
      if (c.club.esPersonal) return c;
    }
    final personal = personalClub;
    return personal == null ? null : ClubAccess(club: personal, roles: const {});
  }

  bool _can(Accion action) => activeClub?.can(action) ?? false;

  /// Whether planning is available in the active club (never in the personal one): plans, assignments, WoDs and
  /// every athlete's sheet and history. Coach and up (permissions by hierarchy).
  bool get canPlan => _can(Accion.planificar);

  /// Whether the user can create and change the active club's exercises, categories and timers (coach and up).
  bool get canEditClubCatalog => _can(Accion.editarCatalogoClub);

  /// Whether the user can change the active club's equipment (club admin and up).
  bool get canEditEquipment => _can(Accion.editarEquipo);

  /// Whether the user can write athletes' references, factors and fixed weights (coach and up).
  bool get canEditReferences => _can(Accion.editarReferencias);

  /// The user's athlete id in the active club, or null when they are not an athlete there.
  String? get athleteId => activeClub?.athleteId;

  /// What the user can do with [plan] of the active club ([PlanAccess]). Without an active club, nothing.
  PlanAccess planAccess(Plan plan) => PlanAccess.of(
    plan,
    userId: user.id,
    roles: activeClub?.roles ?? const {},
    isPlatformAdmin: isPlatformAdmin && activeClub != null,
  );

  bool get canManageMembers => _can(Accion.gestionarMiembros);

  /// Whether the user can see and review the club requests (platform admin, any club).
  bool get canReviewClubRequests => canOnPlatform(Accion.reviewClubRequests, isPlatformAdmin: isPlatformAdmin);

  /// Whether the user can list every club and enter any of them (platform admin).
  bool get canPickAnyClub => canOnPlatform(Accion.listAllClubs, isPlatformAdmin: isPlatformAdmin);

  /// Whether the Preferences tab (catalog, timers, equipment, members, club requests, club picker) is available.
  bool get canConfigure =>
      canEditClubCatalog || canEditEquipment || canManageMembers || canReviewClubRequests || canPickAnyClub;

  /// Whether the user can change [item] (exercise, category, timer): default ones need a platform admin, the club's
  /// a coach and up.
  bool canWriteCatalog(DelClub item) {
    final active = activeClub;
    if (active == null) return false;
    return puedeEscribirCatalogo(item, active.roles, active.club.tipo, esAdminPlataforma: isPlatformAdmin);
  }
}
