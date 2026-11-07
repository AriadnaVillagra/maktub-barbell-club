import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import 'providers.dart';

/// The club's categories (base and own, both states) for the management screen.
final clubCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return const [];
  return ref.watch(catalogRepositoryProvider).categories(clubId);
});

/// Base and club timers, both states.
final clubTimersProvider = FutureProvider<List<Temporizador>>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return const [];
  return ref.watch(catalogAdminRepositoryProvider).timers(clubId);
});

/// The club's equipment (the standard when it never saved one).
final clubTeamProvider = FutureProvider<Equipo?>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return null;
  return ref.watch(catalogAdminRepositoryProvider).team(clubId);
});
