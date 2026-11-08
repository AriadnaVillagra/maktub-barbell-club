/// Where the proposed weight of a set comes from: the athlete's RM or a fixed weight.
///
/// Pure rule over values. See "Bloque / Origen" in reference/DISENO.md and `pesoDeSerie` in the old app.
library;

import 'equipo.dart';
import 'porcentajes.dart';

/// Where a set takes its weight from.
enum LoadSource {
  /// RM × work factor × % of the plan, nearest loadable.
  rm,

  /// The weight the coach loaded for this athlete and exercise, as loaded.
  fixed,
}

/// The proposed weight of a set and where it came from.
class LoadProposal {
  const LoadProposal({required this.source, required this.weightKg});

  final LoadSource source;

  /// Null when there is nothing to propose (missing RM or missing fixed weight): empty, never zero.
  final double? weightKg;

  @override
  bool operator ==(Object other) =>
      other is LoadProposal &&
      other.source == source &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(source, weightKg);

  @override
  String toString() => 'LoadProposal(${source.name}, $weightKg)';
}

/// Decides the source of a set's weight and computes it.
///
/// - [hasReference]: whether the exercise is measured by an RM (it has a reference exercise).
/// - [pct]: the set's % of the plan (null or not positive means the set has no %).
/// - [rm]: the athlete's RM in force for that reference, null if not loaded.
/// - [fixedKg]: the fixed weight the coach loaded for this athlete and exercise, null if none.
///
/// With a reference and a %, the weight comes from the RM through [pesoPorPorcentaje] (null if the RM is
/// missing: it does NOT fall back to the fixed weight, as in the old app). Otherwise it is [fixedKg]
/// exactly as loaded; rounding it to the nearest loadable is a pending decision.
/// [pct] is taken as is: normalize a spreadsheet-style value with `normalizarPct` first.
LoadProposal proposeLoad({
  required bool hasReference,
  required double? pct,
  required double? rm,
  required double? fixedKg,
  required Equipo equipo,
  double workFactor = 100,
}) {
  if (hasReference && pct != null && pct > 0) {
    return LoadProposal(
      source: LoadSource.rm,
      weightKg: pesoPorPorcentaje(
        rm: rm,
        pct: pct,
        equipo: equipo,
        workFactor: workFactor,
      ),
    );
  }
  return LoadProposal(source: LoadSource.fixed, weightKg: fixedKg);
}
