/// Validaciones puras del catálogo (docs/features/F2-catalogo.md, "Reglas"). Las usan el backend al
/// escribir y la app para avisar antes de enviar. Devuelven problemas en vez de lanzar.
library;

import '../modelos/base.dart';
import '../modelos/catalogo.dart';

enum CatalogProblem {
  /// Referencia `propia` en un ejercicio sin carga × repeticiones.
  ownReferenceNeedsLoadAndReps,

  /// La métrica objetivo por defecto no está entre las métricas del ejercicio.
  defaultMetricNotInMetrics,

  /// La referencia `de_otro` apunta a un ejercicio que no existe o no es visible para el club.
  referenceTargetNotVisible,

  /// Cadena de referencias que vuelve sobre sí misma (incluye apuntarse a uno mismo).
  referenceCycle,

  /// Un ejercicio base referencia a uno del club.
  baseReferencesClub,

  /// Categoría, patrón, músculo o sugerencia que no existe o no es visible para el club.
  itemNotVisible,

  /// Un ejercicio base usa una categoría, patrón, grupo o sugerencia del club.
  baseUsesClubItem,

  /// Un nodo base con padre.
  baseNodeWithParent,

  /// El padre no existe o no es visible para el club.
  parentNotVisible,

  /// El padre es del club o es el propio nodo: pasaría de dos niveles (base → hijo del club).
  depthExceeded,

  /// Las notas superan [maxExerciseNotes] caracteres.
  notesTooLong,

  /// La barra del ejercicio no pesa más de 0.
  barNotPositive,
}

/// Máximo de caracteres de las notas de un ejercicio.
const maxExerciseNotes = 500;

/// Lo visible para un club, por id: base + del club. Es lo que el backend lee antes de validar.
class CatalogView {
  const CatalogView({
    this.exercises = const {},
    this.categories = const {},
    this.groups = const {},
    this.patterns = const {},
  });

  CatalogView.of({
    Iterable<Exercise> exercises = const [],
    Iterable<Category> categories = const [],
    Iterable<MuscleGroup> groups = const [],
    Iterable<MovementPattern> patterns = const [],
  }) : this(
         exercises: {for (final e in exercises) e.id: e},
         categories: {for (final c in categories) c.id: c},
         groups: {for (final g in groups) g.id: g},
         patterns: {for (final p in patterns) p.id: p},
       );

  final Map<String, Exercise> exercises;
  final Map<String, Category> categories;
  final Map<String, MuscleGroup> groups;
  final Map<String, MovementPattern> patterns;
}

/// Solo con `propia`: exige carga × repeticiones entre las métricas.
bool isOwnReferenceValid(Exercise e) => e.loadReference.kind != LoadReferenceKind.own || e.measuresLoadTimesReps;

/// Sigue la cadena `de_otro` desde [start] y devuelve los ids recorridos, empezando por [start].
/// Se corta al repetir un id (ciclo), al llegar a un ejercicio sin `de_otro` o a uno que no está en [byId].
List<String> referenceChain(String start, Map<String, Exercise> byId) {
  final chain = <String>[];
  String? current = start;
  while (current != null && !chain.contains(current)) {
    chain.add(current);
    final e = byId[current];
    current = e != null && e.loadReference.kind == LoadReferenceKind.otherExercise ? e.loadReference.exerciseId : null;
  }
  return chain;
}

/// Si seguir las referencias de [start] vuelve a un ejercicio ya visto (A → B → A, A → A).
bool hasReferenceCycle(String start, Map<String, Exercise> byId) {
  final chain = referenceChain(start, byId);
  final last = byId[chain.last];
  if (last == null || last.loadReference.kind != LoadReferenceKind.otherExercise) return false;
  return true;
}

/// Id del ejercicio cuyo RM se usa al cargar [start]: el final de la cadena `de_otro`.
/// Es [start] mismo si tiene RM propio o no referencia a otro. `null` si hay un ciclo.
String? effectiveRmExerciseId(String start, Map<String, Exercise> byId) {
  if (hasReferenceCycle(start, byId)) return null;
  return referenceChain(start, byId).last;
}

/// Un base solo puede referenciar a otro base; uno del club, a base o del club.
bool isReferenceScopeValid(Exercise e, Exercise target) =>
    scopeOf(e) == CatalogScope.club || scopeOf(target) == CatalogScope.base;

/// Valida un ejercicio contra lo visible para su club. [view] debe incluir al propio ejercicio si ya existe
/// (para detectar ciclos); si es nuevo, se lo trata como parte de la vista igualmente.
List<CatalogProblem> validateExercise(Exercise e, CatalogView view) {
  final problems = <CatalogProblem>{};
  final base = scopeOf(e) == CatalogScope.base;

  if (!isOwnReferenceValid(e)) problems.add(CatalogProblem.ownReferenceNeedsLoadAndReps);
  if (e.defaultMetric != null && !e.metrics.contains(e.defaultMetric)) {
    problems.add(CatalogProblem.defaultMetricNotInMetrics);
  }

  if ((e.notes?.length ?? 0) > maxExerciseNotes) problems.add(CatalogProblem.notesTooLong);
  if (e.barKg != null && !(e.barKg! > 0)) problems.add(CatalogProblem.barNotPositive);

  void check(DelClub? item) {
    if (item == null) {
      problems.add(CatalogProblem.itemNotVisible);
    } else if (base && scopeOf(item) == CatalogScope.club) {
      problems.add(CatalogProblem.baseUsesClubItem);
    } else if (!isVisibleTo(item, e.clubId)) {
      problems.add(CatalogProblem.itemNotVisible);
    }
  }

  for (final id in e.categoryIds) {
    check(view.categories[id]);
  }
  if (e.patternId != null) check(view.patterns[e.patternId]);
  for (final m in e.muscles) {
    check(view.groups[m.groupId]);
  }
  for (final id in e.suggestionIds) {
    check(view.exercises[id]);
  }

  if (e.loadReference.kind == LoadReferenceKind.otherExercise) {
    final target = view.exercises[e.loadReference.exerciseId];
    if (target == null) {
      problems.add(CatalogProblem.referenceTargetNotVisible);
    } else if (!isReferenceScopeValid(e, target)) {
      problems.add(CatalogProblem.baseReferencesClub);
    } else if (!isVisibleTo(target, e.clubId)) {
      problems.add(CatalogProblem.referenceTargetNotVisible);
    } else if (hasReferenceCycle(e.id, {...view.exercises, e.id: e})) {
      problems.add(CatalogProblem.referenceCycle);
    }
  }
  return problems.toList();
}

/// Valida un grupo muscular o un patrón: un base no tiene padre; uno del club puede tener un padre base
/// (profundidad máxima: base → hijo del club).
List<CatalogProblem> validateNode(CatalogNode node, Map<String, CatalogNode> visibleById) {
  final parentId = node.parentId;
  if (parentId == null) return const [];
  if (scopeOf(node) == CatalogScope.base) return const [CatalogProblem.baseNodeWithParent];
  final parent = visibleById[parentId];
  if (parent == null || !isVisibleTo(parent, node.clubId)) return const [CatalogProblem.parentNotVisible];
  if (parentId == node.id || scopeOf(parent) != CatalogScope.base || parent.parentId != null) {
    return const [CatalogProblem.depthExceeded];
  }
  return const [];
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Nombre para comparar: sin mayúsculas ni acentos, sin espacios sobrantes.
String normalizeName(String name) {
  final lower = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return [for (final r in lower.runes) _accents[String.fromCharCode(r)] ?? String.fromCharCode(r)].join();
}

/// Si [name] ya lo usa otro elemento de [visible] (el conjunto visible para el club, de un mismo tipo).
/// [exceptId] es el propio elemento al editarlo.
bool isNameTaken<T extends DelClub>(
  String name,
  Iterable<T> visible,
  String Function(T) nameOf,
  String Function(T) idOf, {
  String? exceptId,
}) {
  final wanted = normalizeName(name);
  return visible.any((e) => idOf(e) != exceptId && normalizeName(nameOf(e)) == wanted);
}

bool isExerciseNameTaken(String name, Iterable<Exercise> visible, {String? exceptId}) =>
    isNameTaken(name, visible, (e) => e.name, (e) => e.id, exceptId: exceptId);

bool isCategoryNameTaken(String name, Iterable<Category> visible, {String? exceptId}) =>
    isNameTaken(name, visible, (e) => e.name, (e) => e.id, exceptId: exceptId);

bool isNodeNameTaken(String name, Iterable<CatalogNode> visible, {String? exceptId}) =>
    isNameTaken(name, visible, (e) => e.name, (e) => e.id, exceptId: exceptId);
