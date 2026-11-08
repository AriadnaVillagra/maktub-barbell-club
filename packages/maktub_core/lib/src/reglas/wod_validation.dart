/// WoD validation shared by backend and app (E5.10). It returns every problem, not just the first.
library;

import '../modelos/wod.dart';

enum WodProblemCode { nameEmpty, prescriptionWithoutExercise }

/// A problem and where it is. [prescriptionIndex] is 0-based, null when the problem is the WoD's.
class WodProblem {
  const WodProblem(this.code, {this.prescriptionIndex});

  final WodProblemCode code;
  final int? prescriptionIndex;

  @override
  bool operator ==(Object other) =>
      other is WodProblem &&
      other.code == code &&
      other.prescriptionIndex == prescriptionIndex;

  @override
  int get hashCode => Object.hash(code, prescriptionIndex);

  @override
  String toString() =>
      'WodProblem(${code.name}, prescription: $prescriptionIndex)';
}

/// The problems of [wod]: no name, and prescriptions without an exercise. Sets are not required and any
/// exercise category is valid in a WoD.
List<WodProblem> validateWod(Wod wod) => [
  if (wod.name.trim().isEmpty) const WodProblem(WodProblemCode.nameEmpty),
  for (var i = 0; i < wod.prescriptions.length; i++)
    if (wod.prescriptions[i].exerciseId == null)
      WodProblem(
        WodProblemCode.prescriptionWithoutExercise,
        prescriptionIndex: i,
      ),
];
