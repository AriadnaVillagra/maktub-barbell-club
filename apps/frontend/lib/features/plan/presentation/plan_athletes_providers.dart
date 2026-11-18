import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../access/presentation/providers.dart';
import '../../asignacion/presentation/providers.dart';
import '../../atletas/presentation/providers.dart';
import '../domain/athlete_loads.dart';

/// Who a plan's % and kg are worked out for (E5.16).
class PlanAthletes {
  const PlanAthletes({required this.athletes, required this.assigned});

  static const none = PlanAthletes(athletes: [], assigned: false);

  final List<PlanAthlete> athletes;

  /// True when [athletes] come from the plan's assignment. False when it has none: they are every athlete of the
  /// club, and the coach chooses among them ([planAthleteChoiceProvider]).
  final bool assigned;
}

/// The athletes plan [planId] is for: those in its active assignments now (E6.7), once each; without an active
/// assignment, everyone who was in its latest one. A plan never assigned
/// gets every athlete of the club to choose from. Empty when they cannot be read (who cannot plan does not get here).
final planAthletesProvider = FutureProvider.autoDispose.family<PlanAthletes, String>((ref, planId) async {
  final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return PlanAthletes.none;
  try {
    // Through the screen's provider, so assigning the plan from the editor refreshes this.
    final all = [
      for (final a in (await ref.watch(clubAssignmentsProvider.future)).assignments)
        if (a.planId == planId) a,
    ];
    final active = [
      for (final a in all)
        if (a.status == AssignmentStatus.active) a,
    ];
    final chosen = active.isNotEmpty ? active : all.take(1).toList();

    final people = await ref.watch(athletesProvider.future);
    final names = {for (final a in people) a.id: a.name};
    final Iterable<String> ids;
    if (chosen.isEmpty) {
      ids = [for (final a in people) a.id];
    } else {
      ids = <String>{
        for (final a in chosen)
          ...(a.status == AssignmentStatus.ended ? a.athleteIds : a.currentAthleteIds),
      };
    }
    final athletes = await [
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
    return PlanAthletes(athletes: athletes, assigned: chosen.isNotEmpty);
  } catch (_) {
    // Without them the editor converts nothing; the plan is still edited as before.
    return PlanAthletes.none;
  }
});

/// For a plan without an assignment, the athletes the coach chose to work out % and kg for, by id; null is all of
/// them. Kept while the app is open.
final planAthleteChoiceProvider = NotifierProvider.family<PlanAthleteChoice, Set<String>?, String>(
  PlanAthleteChoice.new,
);

class PlanAthleteChoice extends Notifier<Set<String>?> {
  PlanAthleteChoice(this.planId);

  final String planId;

  @override
  Set<String>? build() => null;

  void choose(Set<String> ids) => state = ids;
}
