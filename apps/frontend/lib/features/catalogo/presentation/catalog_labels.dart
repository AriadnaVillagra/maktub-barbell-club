import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';

/// Spanish names for the wire enums, as the catalog screens show them.
String metricLabel(Metric m) => switch (m) {
  Metric.loadPctRm => 'Carga (% del RM)',
  Metric.fixedLoad => 'Carga fija',
  Metric.bodyweight => 'Peso corporal',
  Metric.reps => 'Repeticiones',
  Metric.time => 'Tiempo',
  Metric.distance => 'Distancia',
  Metric.pace => 'Ritmo',
  Metric.heartRateZone => 'Zona cardíaca',
  Metric.calories => 'Calorías',
  Metric.attempt => 'Intento',
};

String muscleWeightLabel(MuscleWeight w) => switch (w) {
  MuscleWeight.primary => '100 %',
  MuscleWeight.secondary => '50 %',
};

String referenceKindLabel(LoadReferenceKind k) => switch (k) {
  LoadReferenceKind.own => 'RM propio',
  LoadReferenceKind.otherExercise => '% del RM de otro ejercicio',
  LoadReferenceKind.mark => 'Marca propia',
  LoadReferenceKind.pace => 'Ritmo propio',
  LoadReferenceKind.none => 'Sin referencia',
};

/// The backend's message when there is one, a generic one otherwise.
String errorMessage(Object error) =>
    error is ErrorDeApi ? error.mensaje : 'No se pudo completar la operación.';
