import 'dart:convert';
import 'dart:io';

/// Decisions about the real data that the rules alone cannot take (`tool/importar/ajustes.json`). They
/// hold catalog ids only, never personal data. Each step reads its own section; later steps add theirs.
class ImportAdjustments {
  const ImportAdjustments({this.exercises = const ExerciseAdjustments(), this.raw = const {}});

  factory ImportAdjustments.fromJson(Map<String, dynamic> j) => ImportAdjustments(
    exercises: ExerciseAdjustments.fromJson((j['exercises'] as Map?)?.cast<String, dynamic>() ?? const {}),
    raw: j,
  );

  factory ImportAdjustments.fromFile(String path) =>
      ImportAdjustments.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

  final ExerciseAdjustments exercises;

  /// The whole file, for the sections of later steps.
  final Map<String, dynamic> raw;
}

class ExerciseAdjustments {
  const ExerciseAdjustments({this.notBase = const {}, this.sameAs = const {}});

  factory ExerciseAdjustments.fromJson(Map<String, dynamic> j) => ExerciseAdjustments(
    notBase: {for (final id in (j['notBase'] as List? ?? const [])) '$id'},
    sameAs: {for (final e in ((j['sameAs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
  );

  /// Sheet ids that a default exercise also uses for a different exercise (the sheet renamed the row):
  /// they become club exercises instead of matching the default one.
  final Set<String> notBase;

  /// Sheet id → id of a visible exercise that is the same one under another name.
  final Map<String, String> sameAs;
}
