/// Athlete references, work factors and fixed weights (F3; docs/diseno.md, "Referencias del atleta").
library;

import 'base.dart';
import 'cable.dart';
import '../reglas/fechas.dart';
import 'json.dart';

/// What a reference measures. `fcMax` and `zonas` belong to the athlete, not to an exercise.
enum ReferenceType implements ConCable {
  rm('rm'),
  marca('marca'),
  ritmo('ritmo'),
  fcMax('fc_max'),
  zonas('zonas');

  const ReferenceType(this.cable);
  @override
  final String cable;

  /// Whether the reference is tied to an exercise (all but `fc_max` and zones).
  bool get needsExercise => this != fcMax && this != zonas;

  static ReferenceType deCable(Object? v) =>
      desdeCable(values, v, 'Tipo de referencia');
}

/// How a reference came to be.
enum ReferenceOrigin implements ConCable {
  testeado('testeado'),
  estimado('estimado'),
  importado('importado');

  const ReferenceOrigin(this.cable);
  @override
  final String cable;

  static ReferenceOrigin deCable(Object? v) =>
      desdeCable(values, v, 'Origen de referencia');
}

Auditoria _auditoria(Object? v) =>
    Auditoria.fromJson((v as Map).cast<String, dynamic>());

double _number(Object? v, String field) =>
    numOpcional(v) ?? (throw FormatException('Falta $field'));

/// One entry of an athlete's reference history. A new one never overwrites the previous one.
class Reference implements DelClub {
  const Reference({
    required this.id,
    required this.clubId,
    required this.athleteId,
    this.exerciseId,
    required this.type,
    required this.value,
    required this.date,
    required this.origin,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String athleteId;

  /// Null for `fc_max` and zones.
  final String? exerciseId;
  final ReferenceType type;

  /// Kilos for `rm`; the unit of the other types is defined when they are built.
  final double value;

  /// Calendar date from which it applies (`DateTime.utc(y, m, d)`).
  final DateTime date;
  final ReferenceOrigin origin;
  final Auditoria auditoria;

  factory Reference.fromJson(Json j) {
    final type = ReferenceType.deCable(j['tipo']);
    final exerciseId = textoOpcional(j['ejercicioId']);
    if (type.needsExercise && exerciseId == null) {
      throw FormatException(
        'La referencia "${type.cable}" necesita ejercicioId',
      );
    }
    return Reference(
      id: '${j['id']}',
      clubId: '${j['clubId']}',
      athleteId: '${j['atletaId']}',
      exerciseId: exerciseId,
      type: type,
      value: _number(j['valor'], 'valor'),
      date: desdeIsoFecha('${j['fecha']}'),
      origin: ReferenceOrigin.deCable(j['origen']),
      auditoria: _auditoria(j['auditoria']),
    );
  }

  Json toJson() => sinNulos({
    'id': id,
    'clubId': clubId,
    'atletaId': athleteId,
    'ejercicioId': exerciseId,
    'tipo': type.cable,
    'valor': value,
    'fecha': aIsoFecha(date),
    'origen': origin.cable,
    'auditoria': auditoria.toJson(),
  });
}

/// Percentage (100 = no change) of an exercise's RM the athlete trains on, with history.
/// Only applies to RMs (decision P5b).
class WorkFactor implements DelClub {
  const WorkFactor({
    required this.id,
    required this.clubId,
    required this.athleteId,
    required this.exerciseId,
    required this.value,
    required this.date,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String athleteId;
  final String exerciseId;

  /// Percent: 80 means 80 % of the RM.
  final double value;

  /// Calendar date from which it applies.
  final DateTime date;
  final Auditoria auditoria;

  factory WorkFactor.fromJson(Json j) => WorkFactor(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    athleteId: '${j['atletaId']}',
    exerciseId: '${j['ejercicioId']}',
    value: _number(j['valor'], 'valor'),
    date: desdeIsoFecha('${j['fecha']}'),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'atletaId': athleteId,
    'ejercicioId': exerciseId,
    'valor': value,
    'fecha': aIsoFecha(date),
    'auditoria': auditoria.toJson(),
  };
}

/// Weight per athlete and exercise for what is not loaded by percentage (dumbbells...).
class FixedWeight implements DelClub {
  const FixedWeight({
    required this.id,
    required this.clubId,
    required this.athleteId,
    required this.exerciseId,
    required this.kg,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String athleteId;
  final String exerciseId;
  final double kg;
  final Auditoria auditoria;

  factory FixedWeight.fromJson(Json j) => FixedWeight(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    athleteId: '${j['atletaId']}',
    exerciseId: '${j['ejercicioId']}',
    kg: _number(j['kilos'], 'kilos'),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'atletaId': athleteId,
    'ejercicioId': exerciseId,
    'kilos': kg,
    'auditoria': auditoria.toJson(),
  };
}
