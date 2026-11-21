import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../../session/domain/session_manager.dart';
import '../../session/presentation/providers.dart';
import '../data/cached_me_repository.dart';
import '../data/chosen_club_me_repository.dart';
import '../data/http_all_clubs_repository.dart';
import '../data/http_me_repository.dart';
import '../data/shared_preferences_chosen_club_store.dart';
import '../domain/all_clubs_repository.dart';
import '../domain/chosen_club_store.dart';
import '../domain/me.dart';
import '../domain/me_repository.dart';

/// `GET /me` straight from the server. Tests replace it to keep the device's copy in between.
final remoteMeRepositoryProvider = Provider<MeRepository>(
  (ref) => HttpMeRepository(ref.watch(clienteApiProvider)),
);

/// The club the user picked on this device. Tests replace it.
final chosenClubStoreProvider = Provider<ChosenClubStore>((ref) => SharedPreferencesChosenClubStore());

/// `GET /me` with the device's copy as fallback without signal (E7.15), working in the club the user picked.
final meRepositoryProvider = Provider<MeRepository>(
  (ref) => ChosenClubMeRepository(
    CachedMeRepository(
      ref.watch(remoteMeRepositoryProvider),
      ref.watch(localCopyReadsProvider),
    ),
    ref.watch(chosenClubStoreProvider),
  ),
);

/// Every club of the platform (platform admin).
final allClubsRepositoryProvider = Provider<AllClubsRepository>(
  (ref) => HttpAllClubsRepository(ref.watch(clienteApiProvider)),
);

final allClubsProvider = FutureProvider.autoDispose<List<Club>>((ref) => ref.watch(allClubsRepositoryProvider).allClubs());

/// Makes [club] the one the app works in, on this device, and reloads who the user is there: every screen that
/// depends on the active club follows.
Future<void> chooseClub(WidgetRef ref, Club club) async {
  final me = ref.read(meProvider).value;
  if (me == null) return;
  await ref.read(chosenClubStoreProvider).write(me.user.id, club);
  ref.invalidate(meProvider);
  await ref.read(meProvider.future);
}

/// Who the signed-in user is. Null without a session; fetched again whenever the session changes.
final meProvider = FutureProvider<Me?>((ref) async {
  if (ref.watch(sessionControllerProvider) != SessionStatus.signedIn) {
    return null;
  }
  return ref.watch(meRepositoryProvider).fetch();
});

/// Asks `GET /me` again, because an admin may have changed the user's roles from another session, and replaces
/// [meProvider] only when something changed: everything that depends on who the user is (menus, routes, lists)
/// then updates, and nothing reloads when the answer is the same. Without signal the device's copy answers, which
/// changes nothing. Called when the app comes back to the front.
Future<void> refreshMe(WidgetRef ref) async {
  final current = ref.read(meProvider).value;
  if (current == null) return;
  try {
    final fresh = await ref.read(meRepositoryProvider).fetch();
    if (jsonEncode(fresh.toJson()) != jsonEncode(current.toJson())) {
      ref.invalidate(meProvider);
    }
  } on Object {
    // The next return to the front tries again.
  }
}

/// Whether the user can plan in the active club (the Planning tab: athletes, plans, assignments): null while it is
/// not known yet. When `GET /me` fails the answer is false (the API enforces the rule anyway); a retry comes with the
/// next session.
final canPlanProvider = Provider<bool?>((ref) {
  final me = ref.watch(meProvider);
  if (me.isLoading && !me.hasValue) {
    return null;
  }
  return me.value?.canPlan ?? false;
});

/// Whether the Preferences tab is available: null while it is not known yet.
final canConfigureProvider = Provider<bool?>((ref) {
  final me = ref.watch(meProvider);
  if (me.isLoading && !me.hasValue) {
    return null;
  }
  return me.value?.canConfigure ?? false;
});

/// Whether the Perfil tab is available (the user has an athlete id in the active club): null
/// while it is not known yet.
final hasAthleteProfileProvider = Provider<bool?>((ref) {
  final me = ref.watch(meProvider);
  if (me.isLoading && !me.hasValue) {
    return null;
  }
  return me.value?.athleteId != null;
});

/// Whether the user can create and change the active club's exercises, categories and timers (coach and up).
final canEditClubCatalogProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canEditClubCatalog ?? false);

/// Whether the user can change the active club's equipment (club admin and up).
final canEditEquipmentProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canEditEquipment ?? false);

final canEditReferencesProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canEditReferences ?? false);

final canManageMembersProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canManageMembers ?? false);

/// Whether the user reviews club requests (platform admin, who can also do everything in any club).
final isPlatformAdminProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canReviewClubRequests ?? false);

/// Whether the user can list every club and enter any of them (platform admin).
final canPickAnyClubProvider = Provider<bool>((ref) => ref.watch(meProvider).value?.canPickAnyClub ?? false);

/// What the user can do with a given plan ([Me.planAccess]). While `GET /me` is not known, full access: the API
/// enforces the rule anyway, and a coach's own plans are the common case.
final planAccessProvider = Provider<PlanAccess Function(Plan)>((ref) {
  final me = ref.watch(meProvider).value;
  return (plan) => me?.planAccess(plan) ?? PlanAccess.of(plan, userId: plan.auditoria.creadoPor, roles: const {});
});

/// Whether the user can change a given catalog item: exercise, category or timer (see [Me.canWriteCatalog]).
final canWriteCatalogProvider = Provider<bool Function(DelClub)>((ref) {
  final me = ref.watch(meProvider).value;
  return (item) => me?.canWriteCatalog(item) ?? false;
});
