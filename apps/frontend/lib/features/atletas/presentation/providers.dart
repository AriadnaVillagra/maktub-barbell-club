import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../../catalogo/presentation/providers.dart';
import '../data/http_athlete_repository.dart';
import '../domain/athlete_repository.dart';

final athleteRepositoryProvider = Provider<AthleteRepository>(
  (ref) => HttpAthleteRepository(ref.watch(clienteApiProvider)),
);

/// The calendar day the sheet is computed for. Tests override it.
final todayProvider = Provider<DateTime>((ref) => hoy());

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
