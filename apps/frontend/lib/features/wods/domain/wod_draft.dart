import 'package:maktub_core/maktub_core.dart';

/// The WoD being edited in memory: what the form changes before it is sent. Immutable; every operation
/// returns a new draft.
class WodDraft {
  const WodDraft({
    this.name = '',
    this.description = '',
    this.timerId,
    this.prescriptions = const [],
  });

  factory WodDraft.from(Wod wod) => WodDraft(
    name: wod.name,
    description: wod.description ?? '',
    timerId: wod.timerId,
    prescriptions: wod.prescriptions,
  );

  final String name;
  final String description;
  final String? timerId;
  final List<Prescription> prescriptions;

  WodDraft withName(String value) => WodDraft(
    name: value,
    description: description,
    timerId: timerId,
    prescriptions: prescriptions,
  );

  WodDraft withDescription(String value) => WodDraft(
    name: name,
    description: value,
    timerId: timerId,
    prescriptions: prescriptions,
  );

  WodDraft withTimer(String? id) => WodDraft(
    name: name,
    description: description,
    timerId: id,
    prescriptions: prescriptions,
  );

  WodDraft addPrescription(Prescription prescription) =>
      _withList([...prescriptions, prescription]);

  WodDraft removePrescription(int index) =>
      index < 0 || index >= prescriptions.length
      ? this
      : _withList([...prescriptions]..removeAt(index));

  WodDraft updatePrescription(int index, Prescription prescription) =>
      index < 0 || index >= prescriptions.length
      ? this
      : _withList([
          for (final (i, p) in prescriptions.indexed)
            i == index ? prescription : p,
        ]);

  WodDraft _withList(List<Prescription> list) => WodDraft(
    name: name,
    description: description,
    timerId: timerId,
    prescriptions: list,
  );

  /// The problems `validateWod` finds, the same the server reports.
  List<WodProblem> get problems => validateWod(
    Wod(
      id: '',
      clubId: '',
      name: name,
      prescriptions: prescriptions,
      auditoria: Auditoria(creadoPor: '', creadoEn: DateTime.utc(1970)),
    ),
  );

  /// The request body (`Wod.toJson()` without what the server owns). A blank description is left out.
  Json toBody() => {
    'nombre': name.trim(),
    if (description.trim().isNotEmpty) 'descripcion': description.trim(),
    'temporizadorId': ?timerId,
    'prescripciones': [for (final p in prescriptions) p.toJson()],
  };
}
