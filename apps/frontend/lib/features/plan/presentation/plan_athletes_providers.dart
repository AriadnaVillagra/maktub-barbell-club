import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../access/presentation/providers.dart';
import '../../asignacion/presentation/providers.dart';
import '../../atletas/presentation/providers.dart';
import '../domain/athlete_loads.dart';

/// The athletes plan [planId] is for (E5.16): the members of the group of its active assignments, or the athlete of an
/// own one (E8.8), in that order and once each. Without an active assignment, those of its latest one. Empty when it
/// was never assigned, or when they cannot be read (who cannot plan does not get here).
final planAthletesProvider = FutureProvider.autoDispose.family<List<PlanAthlete>, String>((ref, planId) async {
  final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return const [];
  try {
    final repo = ref.watch(assignmentRepositoryProvider);
    final all = [
      for (final a in await repo.assignments(clubId))
        if (a.planId == planId) a,
    ];
    final active = [
      for (final a in all)
        if (a.status == AssignmentStatus.active) a,
    ];
    final chosen = active.isNotEmpty ? active : all.take(1).toList();
    if (chosen.isEmpty) return const [];

    final groups = {for (final g in await repo.groups(clubId)) g.id: g};
    final ids = <String>{
      for (final a in chosen) ...?(a.groupId == null ? null : groups[a.groupId]?.memberIds),
      for (final a in chosen) ?a.athleteId,
    };
    final names = {for (final a in await ref.watch(athletesProvider.future)) a.id: a.name};
    return await [
      for (final id in ids)
        () async {
          final sheet = await ref.watch(athleteSheetProvider(id).future);
          return PlanAthlete(
            id: id,
            name: names[id] ?? 'Atleta',
            references: sheet.references,
            factors: sheet.factors,
          );
        }(),
    ].wait;
  } catch (_) {
    // Without them the editor converts nothing; the plan is still edited as before.
    return const [];
  }
});
