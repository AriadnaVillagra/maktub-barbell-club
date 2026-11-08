import 'package:maktub_core/maktub_core.dart';

/// The Spanish message of [code]. Exhaustive on purpose: a new `WodProblemCode` does not compile until it
/// has its message.
String wodProblemMessage(WodProblemCode code) => switch (code) {
  WodProblemCode.nameEmpty => 'El WoD no tiene nombre.',
  WodProblemCode.prescriptionWithoutExercise => 'Falta elegir el ejercicio.',
};
