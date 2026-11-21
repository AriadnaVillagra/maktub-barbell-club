import 'package:maktub_core/maktub_core.dart';

/// An athlete the plan is for (E5.16), with what their loads are worked out from.
class PlanAthlete {
  const PlanAthlete({
    required this.id,
    required this.name,
    this.references = const [],
    this.factors = const [],
  });

  final String id;
  final String name;
  final List<Reference> references;
  final List<WorkFactor> factors;
}

/// One athlete's RM and work factor in force for an exercise, as the editor converts with them.
class AthleteBasis {
  const AthleteBasis({required this.id, required this.name, required this.rm, this.workFactor = defaultWorkFactor});

  final String id;
  final String name;

  /// Null when the athlete has no RM for the exercise: nothing is converted for them.
  final double? rm;
  final double workFactor;
}

/// The RM and factor in force on [on] of each athlete for the exercise loaded by [rmExerciseId]'s RM (the same
/// resolution as the session's, `setLoadBasis`). Null [rmExerciseId] (an exercise without RM) gives no RM.
List<AthleteBasis> athleteBases(List<PlanAthlete> athletes, String? rmExerciseId, DateTime on) => [
  for (final a in athletes)
    () {
      final basis = setLoadBasis(
        rmExerciseId: rmExerciseId,
        pct: null,
        athleteId: a.id,
        on: on,
        references: a.references,
        factors: a.factors,
      );
      return AthleteBasis(id: a.id, name: a.name, rm: basis.reference?.value, workFactor: basis.workFactor);
    }(),
];

/// Each athlete's frozen % and kilos for a set the coach typed as [pct] or as [kg] (E5.16): the other value comes from
/// the athlete's RM and factor, the kilos rounded to the nearest loadable on [barKg]. Athletes without an RM are left
/// out, and so is everyone when nothing was typed.
Map<String, AthleteSetLoad> athleteLoads({
  required double? pct,
  required double? kg,
  required List<AthleteBasis> athletes,
  required Equipo equipo,
  double? barKg,
}) {
  final typedPct = pct != null && pct > 0 ? pct : null;
  final typedKg = typedPct == null && kg != null && kg > 0 ? kg : null;
  if (typedPct == null && typedKg == null) return const {};
  return {
    for (final a in athletes)
      if (a.rm case final rm? when rm > 0)
        a.id: typedPct != null
            ? AthleteSetLoad(
                pct: typedPct,
                kg: pesoPorPorcentaje(rm: rm, pct: typedPct, equipo: equipo, workFactor: a.workFactor, barKg: barKg),
              )
            : AthleteSetLoad(pct: pctDesdePeso(typedKg!, rm, workFactor: a.workFactor), kg: typedKg),
  };
}

/// "Andi 50 kg · 62,5 % · Ari 50 kg · 70 %", in [athletes]' order; empty when the set has none of theirs.
String athleteLoadsSummary(Map<String, AthleteSetLoad> loads, List<AthleteBasis> athletes, String Function(double) number) =>
    [
      for (final a in athletes)
        if (loads[a.id] case final load?)
          [
            a.name,
            if (load.kg != null) '${number(load.kg!)} kg',
            if (load.pct != null) '${number(load.pct!)} %',
          ].join(' '),
    ].join(' · ');

/// Kilos per athlete in a set by % (Ari, 2026-11-21): in a plan for several athletes, each athlete's line under the
/// set shows what their RM suggests, and the coach types their kilos by hand. Left blank, the athlete keeps the
/// suggestion frozen above ([athleteLoads]), so the plan publishes without typing them all.

/// [athlete]'s load for kilos [kg] the coach typed by hand: the % of their RM they amount to (with their factor, as
/// the session derives it), none without an RM.
AthleteSetLoad manualAthleteLoad(double kg, AthleteBasis athlete) => AthleteSetLoad(
  pct: switch (athlete.rm) {
    final rm? when rm > 0 => pctDesdePeso(kg, rm, workFactor: athlete.workFactor),
    _ => null,
  },
  kg: kg,
  manualKg: true,
);

/// The entries of [byAthlete] the coach typed by hand: working the set out again keeps them.
Map<String, AthleteSetLoad> manualLoads(Map<String, AthleteSetLoad> byAthlete) => {
  for (final e in byAthlete.entries)
    if (e.value.manualKg) e.key: e.value,
};

/// What [athlete]'s RM suggests for a set typed as [setPct] or as [setKg], given [suggested] (their entry of
/// [athleteLoads] for it): "Ari · RM 80 kg × 65 % = 52 kg", "Ari · RM 80 kg · 50 kg = 62,5 %", with
/// " (factor 95 %)" when their factor is not neutral; "Ari · RM 80 kg" with nothing typed, "Ari · sin RM" without one.
String athleteSuggestion(
  AthleteBasis athlete, {
  required double? setPct,
  required AthleteSetLoad? suggested,
  required String Function(double) number,
}) {
  final rm = athlete.rm;
  if (rm == null || rm <= 0) return '${athlete.name} · sin RM';
  final base = '${athlete.name} · RM ${number(rm)} kg';
  final factor = athlete.workFactor == defaultWorkFactor ? '' : ' (factor ${number(athlete.workFactor)} %)';
  return switch (suggested) {
    AthleteSetLoad(pct: final pct?, kg: final kg?) when setPct != null && setPct > 0 =>
      '$base × ${number(pct)} % = ${number(kg)} kg$factor',
    AthleteSetLoad(pct: final pct?, kg: final kg?) => '$base · ${number(kg)} kg = ${number(pct)} %$factor',
    _ => base,
  };
}
