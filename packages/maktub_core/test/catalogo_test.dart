import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 7, 10));

Exercise _ex(
  String id, {
  String clubId = 'c1',
  String? name,
  List<Metric> metrics = const [Metric.loadPctRm, Metric.reps],
  LoadReference ref = const LoadReference.none(),
  List<String> categories = const [],
  String? pattern,
  List<MuscleShare> muscles = const [],
  List<String> suggestions = const [],
  Metric? defaultMetric,
}) => Exercise(
  id: id,
  clubId: clubId,
  name: name ?? id,
  metrics: metrics,
  loadReference: ref,
  categoryIds: categories,
  patternId: pattern,
  muscles: muscles,
  suggestionIds: suggestions,
  defaultMetric: defaultMetric,
  auditoria: _audit,
);

Category _cat(String id, String clubId) => Category(id: id, clubId: clubId, name: id, auditoria: _audit);
MuscleGroup _grp(String id, String clubId, {String? parent}) =>
    MuscleGroup(id: id, clubId: clubId, name: id, parentId: parent, auditoria: _audit);

void main() {
  group('JSON', () {
    test('Exercise round trip con todos los campos', () {
      final e = Exercise(
        id: 'e1',
        clubId: clubPlataforma,
        name: 'Press militar',
        categoryIds: ['c-fuerza'],
        metrics: [Metric.loadPctRm, Metric.reps, Metric.attempt],
        defaultMetric: Metric.loadPctRm,
        patternId: 'p-empuje',
        muscles: [
          const MuscleShare(groupId: 'g-hombro', weight: MuscleWeight.primary),
          const MuscleShare(groupId: 'g-triceps', weight: MuscleWeight.secondary),
        ],
        loadReference: const LoadReference.otherExercise('bench'),
        suggestionIds: ['mov'],
        notes: 'Estricto',
        status: CatalogStatus.archived,
        auditoria: _audit,
      );
      final copy = Exercise.fromJson(e.toJson());
      expect(copy.toJson(), e.toJson());
      expect(copy.scope, CatalogScope.base);
      expect(copy.loadReference, const LoadReference.otherExercise('bench'));
      expect(copy.status, CatalogStatus.archived);
      expect(copy.muscles.last.weight.factor, 0.5);
      expect(Metric.values.map((m) => Metric.deCable(m.cable)), Metric.values);
    });

    test('Exercise mínimo usa valores por defecto', () {
      final copy = Exercise.fromJson(_ex('e1').toJson());
      expect(copy.loadReference.kind, LoadReferenceKind.none);
      expect(copy.status, CatalogStatus.active);
      expect(copy.scope, CatalogScope.club);
    });

    test('LoadReference de_otro exige ejercicioId y los demás tipos viajan', () {
      expect(() => LoadReference.fromJson({'tipo': 'de_otro'}), throwsFormatException);
      for (final k in LoadReferenceKind.values.where((k) => k != LoadReferenceKind.otherExercise)) {
        expect(LoadReference.fromJson(LoadReference(k).toJson()).kind, k);
      }
    });

    test('Category, MuscleGroup y MovementPattern round trip', () {
      final c = _cat('c1', 'club1');
      expect(Category.fromJson(c.toJson()).toJson(), c.toJson());
      final g = _grp('g2', 'club1', parent: 'g1');
      final g2 = MuscleGroup.fromJson(g.toJson());
      expect(g2.parentId, 'g1');
      expect(g2.toJson(), g.toJson());
      final p = MovementPattern(id: 'p1', clubId: clubPlataforma, name: 'Sentadilla', auditoria: _audit);
      final p2 = MovementPattern.fromJson(p.toJson());
      expect(p2.parentId, isNull);
      expect(p2.scope, CatalogScope.base);
      expect(p2.toJson(), p.toJson());
    });

    test('valores desconocidos se rechazan', () {
      expect(() => Metric.deCable('xx'), throwsFormatException);
      expect(() => CatalogStatus.deCable('xx'), throwsFormatException);
    });
  });

  group('referencia propia', () {
    test('exige carga y repeticiones', () {
      const own = LoadReference.own();
      expect(isOwnReferenceValid(_ex('a', ref: own)), isTrue);
      expect(isOwnReferenceValid(_ex('a', ref: own, metrics: [Metric.fixedLoad, Metric.reps])), isTrue);
      expect(isOwnReferenceValid(_ex('a', ref: own, metrics: [Metric.reps])), isFalse);
      expect(isOwnReferenceValid(_ex('a', ref: own, metrics: [Metric.loadPctRm])), isFalse);
      expect(isOwnReferenceValid(_ex('a', ref: own, metrics: [Metric.time])), isFalse);
      expect(isOwnReferenceValid(_ex('a', metrics: [Metric.time])), isTrue);
    });

    test('validateExercise la rechaza', () {
      final e = _ex('a', ref: const LoadReference.own(), metrics: [Metric.time]);
      expect(validateExercise(e, CatalogView.of(exercises: [e])), [CatalogProblem.ownReferenceNeedsLoadAndReps]);
    });
  });

  group('ciclos y RM efectivo', () {
    test('A -> B -> A se rechaza', () {
      final a = _ex('a', ref: const LoadReference.otherExercise('b'));
      final b = _ex('b', ref: const LoadReference.otherExercise('a'));
      final view = CatalogView.of(exercises: [a, b]);
      expect(hasReferenceCycle('a', view.exercises), isTrue);
      expect(validateExercise(a, view), contains(CatalogProblem.referenceCycle));
      expect(effectiveRmExerciseId('a', view.exercises), isNull);
    });

    test('apuntarse a uno mismo es un ciclo', () {
      final a = _ex('a', ref: const LoadReference.otherExercise('a'));
      expect(validateExercise(a, CatalogView.of(exercises: [a])), contains(CatalogProblem.referenceCycle));
    });

    test('un ciclo que se cierra al editar se detecta con la versión nueva', () {
      final a = _ex('a');
      final b = _ex('b', ref: const LoadReference.otherExercise('a'));
      final newA = _ex('a', ref: const LoadReference.otherExercise('b'));
      final view = CatalogView.of(exercises: [a, b]);
      expect(validateExercise(newA, view), contains(CatalogProblem.referenceCycle));
    });

    test('el RM efectivo es el final de la cadena', () {
      final bench = _ex('bench', ref: const LoadReference.own());
      final press = _ex('press', ref: const LoadReference.otherExercise('bench'));
      final push = _ex('push', ref: const LoadReference.otherExercise('press'));
      final byId = CatalogView.of(exercises: [bench, press, push]).exercises;
      expect(referenceChain('push', byId), ['push', 'press', 'bench']);
      expect(effectiveRmExerciseId('push', byId), 'bench');
      expect(effectiveRmExerciseId('bench', byId), 'bench');
      expect(hasReferenceCycle('push', byId), isFalse);
      expect(validateExercise(push, CatalogView.of(exercises: [bench, press, push])), isEmpty);
    });

    test('un destino inexistente no es visible', () {
      final a = _ex('a', ref: const LoadReference.otherExercise('zz'));
      expect(validateExercise(a, CatalogView.of(exercises: [a])), [CatalogProblem.referenceTargetNotVisible]);
    });
  });

  group('ámbito', () {
    test('un base solo referencia a otro base', () {
      final baseBench = _ex('bench', clubId: clubPlataforma);
      final clubBench = _ex('cb');
      final baseRef = _ex('p', clubId: clubPlataforma, ref: const LoadReference.otherExercise('cb'));
      expect(
        validateExercise(baseRef, CatalogView.of(exercises: [clubBench, baseRef])),
        contains(CatalogProblem.baseReferencesClub),
      );
      final baseOk = _ex('p', clubId: clubPlataforma, ref: const LoadReference.otherExercise('bench'));
      expect(validateExercise(baseOk, CatalogView.of(exercises: [baseBench, baseOk])), isEmpty);
    });

    test('uno del club referencia a base o del club', () {
      final baseBench = _ex('bench', clubId: clubPlataforma);
      final clubBench = _ex('cb');
      final toBase = _ex('x', ref: const LoadReference.otherExercise('bench'));
      final toClub = _ex('y', ref: const LoadReference.otherExercise('cb'));
      final view = CatalogView.of(exercises: [baseBench, clubBench, toBase, toClub]);
      expect(validateExercise(toBase, view), isEmpty);
      expect(validateExercise(toClub, view), isEmpty);
    });

    test('un ejercicio de otro club no es visible', () {
      final other = _ex('o', clubId: 'c2');
      final a = _ex('a', ref: const LoadReference.otherExercise('o'));
      expect(validateExercise(a, CatalogView.of(exercises: [other, a])), [CatalogProblem.referenceTargetNotVisible]);
    });

    test('músculos, patrón, categorías y sugerencias deben ser visibles', () {
      final e = _ex(
        'a',
        categories: ['cat'],
        pattern: 'pat',
        muscles: [const MuscleShare(groupId: 'g', weight: MuscleWeight.primary)],
        suggestions: ['s'],
      );
      final pat = MovementPattern(id: 'pat', clubId: 'c1', name: 'pat', auditoria: _audit);
      final ok = CatalogView.of(
        exercises: [e, _ex('s')],
        categories: [_cat('cat', 'c1')],
        groups: [_grp('g', clubPlataforma)],
        patterns: [pat],
      );
      expect(validateExercise(e, ok), isEmpty);
      expect(validateExercise(e, const CatalogView()), [CatalogProblem.itemNotVisible]);
      final foreign = CatalogView.of(
        exercises: [e, _ex('s')],
        categories: [_cat('cat', 'c2')],
        groups: [_grp('g', 'c2')],
        patterns: [pat],
      );
      expect(validateExercise(e, foreign), [CatalogProblem.itemNotVisible]);
    });

    test('un base no usa categorías, grupos, patrones ni sugerencias del club', () {
      final e = _ex(
        'a',
        clubId: clubPlataforma,
        categories: ['cat'],
        muscles: [const MuscleShare(groupId: 'g', weight: MuscleWeight.primary)],
        suggestions: ['s'],
      );
      final view = CatalogView.of(
        exercises: [
          e,
          _ex('s', clubId: 'c1'),
        ],
        categories: [_cat('cat', 'c1')],
        groups: [_grp('g', 'c1')],
      );
      // Un base evaluado desde la plataforma no ve lo del club, pero la regla específica prima.
      expect(validateExercise(e, view), [CatalogProblem.baseUsesClubItem]);
      final clubExercise = _ex('b', clubId: clubPlataforma, categories: ['cat2']);
      final cat2 = Category(id: 'cat2', clubId: clubPlataforma, name: 'x', auditoria: _audit);
      expect(validateExercise(clubExercise, CatalogView.of(exercises: [clubExercise], categories: [cat2])), isEmpty);
    });

    test('la métrica objetivo debe estar entre las métricas', () {
      final e = _ex('a', metrics: [Metric.time], defaultMetric: Metric.distance);
      expect(validateExercise(e, CatalogView.of(exercises: [e])), [CatalogProblem.defaultMetricNotInMetrics]);
    });
  });

  group('profundidad de grupos', () {
    final root = _grp('hombro', clubPlataforma);
    final child = _grp('lateral', 'c1', parent: 'hombro');
    final byId = <String, CatalogNode>{'hombro': root, 'lateral': child};

    test('sin padre siempre vale', () {
      expect(validateNode(root, byId), isEmpty);
      expect(validateNode(_grp('extra', 'c1'), byId), isEmpty);
    });

    test('hijo del club bajo un base vale', () {
      expect(validateNode(child, byId), isEmpty);
    });

    test('un base no tiene padre', () {
      expect(validateNode(_grp('x', clubPlataforma, parent: 'hombro'), byId), [CatalogProblem.baseNodeWithParent]);
    });

    test('un nieto supera los dos niveles', () {
      expect(validateNode(_grp('fino', 'c1', parent: 'lateral'), byId), [CatalogProblem.depthExceeded]);
      expect(validateNode(_grp('lateral', 'c1', parent: 'lateral'), byId), [CatalogProblem.depthExceeded]);
    });

    test('padre inexistente o de otro club', () {
      expect(validateNode(_grp('x', 'c1', parent: 'nope'), byId), [CatalogProblem.parentNotVisible]);
      final foreign = _grp('f', 'c2');
      expect(validateNode(_grp('x', 'c1', parent: 'f'), {'f': foreign}), [CatalogProblem.parentNotVisible]);
    });

    test('vale igual para patrones', () {
      final p = MovementPattern(id: 'p', clubId: clubPlataforma, name: 'p', auditoria: _audit);
      final h = MovementPattern(id: 'h', clubId: 'c1', name: 'h', parentId: 'p', auditoria: _audit);
      expect(validateNode(h, {'p': p, 'h': h}), isEmpty);
    });
  });

  group('nombres únicos', () {
    test('normalizeName ignora mayúsculas, acentos y espacios', () {
      expect(normalizeName('  Sentadilla   FRONTAL '), 'sentadilla frontal');
      expect(normalizeName('Tracción Ñandú'), 'traccion nandu');
    });

    test('detecta duplicados dentro de lo visible', () {
      final visible = [_ex('1', name: 'Tracción', clubId: clubPlataforma), _ex('2', name: 'Press')];
      expect(isExerciseNameTaken('TRACCION', visible), isTrue);
      expect(isExerciseNameTaken('press ', visible), isTrue);
      expect(isExerciseNameTaken('Remo', visible), isFalse);
    });

    test('al editar se excluye el propio elemento', () {
      final visible = [_ex('1', name: 'Press')];
      expect(isExerciseNameTaken('press', visible, exceptId: '1'), isFalse);
    });

    test('categorías y grupos', () {
      expect(
        isCategoryNameTaken('Wod', [Category(id: 'c', clubId: 'plataforma', name: 'WOD', auditoria: _audit)]),
        isTrue,
      );
      expect(isNodeNameTaken('Hombro', [_grp('g', clubPlataforma).let('hombro')]), isTrue);
    });
  });
}

extension on MuscleGroup {
  MuscleGroup let(String newName) =>
      MuscleGroup(id: id, clubId: clubId, name: newName, parentId: parentId, auditoria: auditoria);
}
