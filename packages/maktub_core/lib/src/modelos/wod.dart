/// A WoD saved in the club's library (E5.10): a reusable group of prescriptions that the coach copies into a
/// plan block. Adding it to a block copies it; editing the WoD later never changes the plans that used it.
///
/// It reuses [Prescription] as it is, so a WoD's prescriptions may have no sets and any exercise category is
/// valid. Identifiers are English; the wire (JSON keys) stays Spanish like the other contracts. The model never
/// throws on an incomplete WoD; `validateWod` returns the problems.
library;

import 'base.dart';
import 'json.dart';
import 'plan.dart';

class Wod implements DelClub {
  const Wod({
    required this.id,
    required this.clubId,
    required this.name,
    this.description,
    this.timerId,
    this.prescriptions = const [],
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String name;
  final String? description;

  /// Id of a catalog timer (an AMRAP, an EMOM...), or null for a WoD without one.
  final String? timerId;
  final List<Prescription> prescriptions;
  final Auditoria auditoria;

  factory Wod.fromJson(Json j) => Wod(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre'] ?? ''}',
    description: textoOpcional(j['descripcion']),
    timerId: textoOpcional(j['temporizadorId']),
    prescriptions: [
      for (final p in listaJson(j['prescripciones'])) Prescription.fromJson(p),
    ],
    auditoria: Auditoria.fromJson(
      (j['auditoria'] as Map).cast<String, dynamic>(),
    ),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'nombre': name,
    ...sinNulos({'descripcion': description, 'temporizadorId': timerId}),
    'prescripciones': [for (final p in prescriptions) p.toJson()],
    'auditoria': auditoria.toJson(),
  };
}
