import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../../catalogo/presentation/providers.dart';
import '../data/cached_athlete_repository.dart';
import '../data/http_athlete_repository.dart';
import '../domain/athlete_repository.dart';

/// Athletes straight from the server. Tests replace it to keep the device's copy in between.
final remoteAthleteRepositoryProvider = Provider<AthleteRepository>(
  (ref) => HttpAthleteRepository(ref.watch(clienteApiProvider)),
);

/// The athlete list with the device's copy as fallback without signal (E7.15); sheets and writes from the server.
final athleteRepositoryProvider = Provider<AthleteRepository>(
  (ref) => CachedAthleteRepository(
    ref.watch(remoteAthleteRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
);

/// Today's calendar date on the device, which places the user in their plan and dates the sessions they open. It
/// moves at midnight: the app can stay open for days, and a stale date would open the day's session on another
/// date. A timer due while the app sleeps runs when it wakes. Tests override it.
final todayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(midnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return soloFecha(now);
});

/// The athletes of the active club, by name.
final athletesProvider = FutureProvider<List<AthleteSummary>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(athleteRepositoryProvider).athletes(clubId);
});

/// The sheet of an athlete of the active club. Throws the backend's `ErrorDeApi` on failure.
final athleteSheetProvider = FutureProvider.family<AthleteSheet, String>((
  ref,
  athleteId,
) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return AthleteSheet(athleteId: athleteId);
  return ref.watch(athleteRepositoryProvider).sheet(clubId, athleteId);
});

/// Exercise names by id (every state, so archived exercises still read right on old references).
final exerciseNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const {};
  final exercises = await ref
      .watch(catalogRepositoryProvider)
      .exercises(clubId);
  return {for (final e in exercises) e.id: e.name};
});
