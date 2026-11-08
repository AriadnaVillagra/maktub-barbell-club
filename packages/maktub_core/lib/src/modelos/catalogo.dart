/// Catálogo (F2; docs/diseno.md, "Catálogo" y "Métricas de un ejercicio"): ejercicios, categorías,
/// grupos musculares y patrones de movimiento, en dos ámbitos: base (de plataforma) y del club.
///
/// Identificadores en inglés; el cable (claves JSON y valores de enums) sigue en español como el resto
/// de los contratos. El ámbito no es un campo aparte: se deduce del `clubId` (base = [clubPlataforma]).
library;

import 'base.dart';
import 'cable.dart';
import 'json.dart';

/// Ámbito de un documento del catálogo.
enum CatalogScope { base, club }

/// Ámbito de un documento a partir de su `clubId`.
CatalogScope scopeOf(DelClub doc) => doc.clubId == clubPlataforma ? CatalogScope.base : CatalogScope.club;

/// Si [doc] lo ve [clubId]: lo de plataforma más lo del propio club.
bool isVisibleTo(DelClub doc, String clubId) => doc.clubId == clubPlataforma || doc.clubId == clubId;

/// `activo` se ofrece en el selector; `archivado` deja de ofrecerse pero sigue resolviéndose donde ya se usa.
enum CatalogStatus implements ConCable {
  active('activo'),
  archived('archivado');

  const CatalogStatus(this.cable);
  @override
  final String cable;

  static CatalogStatus deCable(Object? v) => desdeCable(values, v, 'Estado de catálogo');
}

/// Qué se mide en un ejercicio (diseño §3.5).
enum Metric implements ConCable {
  loadPctRm('carga_pct_rm'),
  fixedLoad('carga_fija'),
  bodyweight('peso_corporal'),
  reps('repeticiones'),
  time('tiempo'),
  distance('distancia'),
  pace('ritmo'),
  heartRateZone('zona_cardiaca'),
  calories('calorias'),
  attempt('intento');

  const Metric(this.cable);
  @override
  final String cable;

  /// Carga (por % de RM o fija): una de las dos partes de "carga × repeticiones".
  bool get isLoad => this == loadPctRm || this == fixedLoad;

  static Metric deCable(Object? v) => desdeCable(values, v, 'Métrica');
}

/// Peso de un músculo en un ejercicio: una serie suma [factor] series al grupo.
enum MuscleWeight implements ConCable {
  primary('principal', 1),
  secondary('secundario', 0.5);

  const MuscleWeight(this.cable, this.factor);
  @override
  final String cable;
  final double factor;

  static MuscleWeight deCable(Object? v) => desdeCable(values, v, 'Peso muscular');
}

/// Contra qué se prescribe la carga de un ejercicio.
enum LoadReferenceKind implements ConCable {
  /// Tiene RM propio. Solo vale si mide carga × repeticiones.
  own('propia'),

  /// Se carga como % del RM de otro ejercicio ([LoadReference.exerciseId]).
  otherExercise('de_otro'),

  /// Cardio contra una marca propia.
  mark('marca'),

  /// Cardio contra un ritmo propio.
  pace('ritmo'),

  /// Kilaje fijo por atleta, peso corporal o valores absolutos.
  none('ninguna');

  const LoadReferenceKind(this.cable);
  @override
  final String cable;

  static LoadReferenceKind deCable(Object? v) => desdeCable(values, v, 'Referencia de carga');
}

class LoadReference {
  const LoadReference(this.kind, {this.exerciseId})
    : assert((kind == LoadReferenceKind.otherExercise) == (exerciseId != null));

  const LoadReference.none() : this(LoadReferenceKind.none);
  const LoadReference.own() : this(LoadReferenceKind.own);
  const LoadReference.otherExercise(String exerciseId) : this(LoadReferenceKind.otherExercise, exerciseId: exerciseId);

  final LoadReferenceKind kind;

  /// Solo con [LoadReferenceKind.otherExercise].
  final String? exerciseId;

  factory LoadReference.fromJson(Json j) {
    final kind = LoadReferenceKind.deCable(j['tipo']);
    final id = textoOpcional(j['ejercicioId']);
    if (kind == LoadReferenceKind.otherExercise && id == null) {
      throw const FormatException('La referencia "de_otro" necesita ejercicioId');
    }
    return LoadReference(kind, exerciseId: kind == LoadReferenceKind.otherExercise ? id : null);
  }

  Json toJson() => sinNulos({'tipo': kind.cable, 'ejercicioId': exerciseId});

  @override
  bool operator ==(Object other) => other is LoadReference && other.kind == kind && other.exerciseId == exerciseId;

  @override
  int get hashCode => Object.hash(kind, exerciseId);
}

/// Un grupo muscular con su peso en un ejercicio.
class MuscleShare {
  const MuscleShare({required this.groupId, required this.weight});

  final String groupId;
  final MuscleWeight weight;

  factory MuscleShare.fromJson(Json j) =>
      MuscleShare(groupId: '${j['grupoId']}', weight: MuscleWeight.deCable(j['peso']));

  Json toJson() => {'grupoId': groupId, 'peso': weight.cable};

  @override
  bool operator ==(Object other) => other is MuscleShare && other.groupId == groupId && other.weight == weight;

  @override
  int get hashCode => Object.hash(groupId, weight);
}

Auditoria _auditoria(Object? v) => Auditoria.fromJson((v as Map).cast<String, dynamic>());

List<String> _ids(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];

/// Entrada del catálogo, base o del club.
class Exercise implements DelClub {
  const Exercise({
    required this.id,
    required this.clubId,
    required this.name,
    this.categoryIds = const [],
    this.metrics = const [],
    this.defaultMetric,
    this.patternId,
    this.muscles = const [],
    this.loadReference = const LoadReference.none(),
    this.suggestionIds = const [],
    this.notes,
    this.barKg,
    this.status = CatalogStatus.active,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String name;

  /// Definen en qué bloques se puede elegir.
  final List<String> categoryIds;
  final List<Metric> metrics;

  /// Métrica que la serie fija como objetivo si el plan no dice otra. Debe estar en [metrics].
  final Metric? defaultMetric;

  /// Id de un [MovementPattern].
  final String? patternId;
  final List<MuscleShare> muscles;
  final LoadReference loadReference;

  /// Ids de ejercicios que suele acompañar (relación dirigida).
  final List<String> suggestionIds;
  final String? notes;

  /// Barra del inventario con la que se carga (kg). Nula, o si el club no la tiene: su barra por defecto.
  /// `noBarKg` (0): el ejercicio no usa barra.
  final double? barKg;
  final CatalogStatus status;
  final Auditoria auditoria;

  CatalogScope get scope => scopeOf(this);
  bool get isActive => status == CatalogStatus.active;

  /// Mide carga (por % de RM o fija) y repeticiones: requisito de la referencia `propia`.
  bool get measuresLoadTimesReps => metrics.contains(Metric.reps) && metrics.any((m) => m.isLoad);

  Exercise copyWith({
    String? name,
    List<String>? categoryIds,
    List<Metric>? metrics,
    Metric? defaultMetric,
    String? patternId,
    List<MuscleShare>? muscles,
    LoadReference? loadReference,
    List<String>? suggestionIds,
    String? notes,
    double? barKg,
    CatalogStatus? status,
    Auditoria? auditoria,
  }) => Exercise(
    id: id,
    clubId: clubId,
    name: name ?? this.name,
    categoryIds: categoryIds ?? this.categoryIds,
    metrics: metrics ?? this.metrics,
    defaultMetric: defaultMetric ?? this.defaultMetric,
    patternId: patternId ?? this.patternId,
    muscles: muscles ?? this.muscles,
    loadReference: loadReference ?? this.loadReference,
    suggestionIds: suggestionIds ?? this.suggestionIds,
    notes: notes ?? this.notes,
    barKg: barKg ?? this.barKg,
    status: status ?? this.status,
    auditoria: auditoria ?? this.auditoria,
  );

  factory Exercise.fromJson(Json j) => Exercise(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre']}',
    categoryIds: _ids(j['categorias']),
    metrics: [for (final m in (j['metricas'] as List? ?? const [])) Metric.deCable(m)],
    defaultMetric: j['metricaObjetivo'] == null ? null : Metric.deCable(j['metricaObjetivo']),
    patternId: textoOpcional(j['patronId']),
    muscles: [for (final m in listaJson(j['musculos'])) MuscleShare.fromJson(m)],
    loadReference: j['referencia'] == null
        ? const LoadReference.none()
        : LoadReference.fromJson((j['referencia'] as Map).cast<String, dynamic>()),
    suggestionIds: _ids(j['sugerencias']),
    notes: textoOpcional(j['notas']),
    barKg: (j['barraKg'] as num?)?.toDouble(),
    status: j['estado'] == null ? CatalogStatus.active : CatalogStatus.deCable(j['estado']),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => sinNulos({
    'id': id,
    'clubId': clubId,
    'nombre': name,
    'categorias': categoryIds,
    'metricas': [for (final m in metrics) m.cable],
    'metricaObjetivo': defaultMetric?.cable,
    'patronId': patternId,
    'musculos': [for (final m in muscles) m.toJson()],
    'referencia': loadReference.toJson(),
    'sugerencias': suggestionIds,
    'notas': notes,
    'barraKg': barKg,
    'estado': status.cable,
    'auditoria': auditoria.toJson(),
  });
}

/// Etiqueta ("fuerza", "accesorio", "wod"...) que filtra qué ejercicios admite un bloque.
class Category implements DelClub {
  const Category({
    required this.id,
    required this.clubId,
    required this.name,
    this.status = CatalogStatus.active,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String name;
  final CatalogStatus status;
  final Auditoria auditoria;

  CatalogScope get scope => scopeOf(this);

  Category copyWith({String? name, CatalogStatus? status, Auditoria? auditoria}) => Category(
    id: id,
    clubId: clubId,
    name: name ?? this.name,
    status: status ?? this.status,
    auditoria: auditoria ?? this.auditoria,
  );

  factory Category.fromJson(Json j) => Category(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre']}',
    status: j['estado'] == null ? CatalogStatus.active : CatalogStatus.deCable(j['estado']),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'nombre': name,
    'estado': status.cable,
    'auditoria': auditoria.toJson(),
  };
}

/// Elemento de un árbol de dos niveles: un nodo base y, debajo, hijos del club.
abstract class CatalogNode implements DelClub {
  const CatalogNode({
    required this.id,
    required this.clubId,
    required this.name,
    this.parentId,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String name;

  /// Solo en nodos del club, y apunta a un nodo base.
  final String? parentId;
  final Auditoria auditoria;

  CatalogScope get scope => scopeOf(this);
}

/// Grupo muscular. Un grupo del club puede subdividir uno base ("deltoides lateral" bajo "hombro").
class MuscleGroup extends CatalogNode {
  const MuscleGroup({
    required super.id,
    required super.clubId,
    required super.name,
    super.parentId,
    required super.auditoria,
  });

  factory MuscleGroup.fromJson(Json j) => MuscleGroup(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre']}',
    parentId: textoOpcional(j['padreId']),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() =>
      sinNulos({'id': id, 'clubId': clubId, 'nombre': name, 'padreId': parentId, 'auditoria': auditoria.toJson()});
}

/// Patrón de movimiento (sentadilla, bisagra, empuje horizontal...). Mismo esquema que [MuscleGroup].
class MovementPattern extends CatalogNode {
  const MovementPattern({
    required super.id,
    required super.clubId,
    required super.name,
    super.parentId,
    required super.auditoria,
  });

  factory MovementPattern.fromJson(Json j) => MovementPattern(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre']}',
    parentId: textoOpcional(j['padreId']),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() =>
      sinNulos({'id': id, 'clubId': clubId, 'nombre': name, 'padreId': parentId, 'auditoria': auditoria.toJson()});
}
