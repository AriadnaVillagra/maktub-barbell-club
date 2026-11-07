// Validates the proposed base catalog (tool/semilla/catalogo_base.json) against the maktub_core rules,
// so the seed script (E2.7) can trust it. Runs from apps/backend (`dart test`).
import 'dart:convert';
import 'dart:io';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

/// Ids without own muscles or pattern on purpose: generic WoD formats and the "approach sets" warm-up.
const _withoutMuscles = {
  'wod_amrap5',
  'wod_amrap4',
  'wod_tabata',
  'wod_emom10',
  'cal_aprox',
};

void main() {
  final raw = jsonDecode(
    File('tool/semilla/catalogo_base.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final audit = Auditoria.nueva(
    'seed',
    ahora: DateTime.utc(2026, 11, 7),
  ).toJson();

  List<Map<String, dynamic>> items(String key) => [
    for (final e in raw[key] as List)
      {
        ...(e as Map<String, dynamic>),
        'clubId': clubPlataforma,
        'auditoria': audit,
      },
  ];

  final categories = [
    for (final j in items('categorias')) Category.fromJson(j),
  ];
  final groups = [
    for (final j in items('gruposMusculares')) MuscleGroup.fromJson(j),
  ];
  final patterns = [
    for (final j in items('patrones')) MovementPattern.fromJson(j),
  ];
  final exercises = [for (final j in items('ejercicios')) Exercise.fromJson(j)];
  final timers = [
    for (final j in items('temporizadores')) Temporizador.fromJson(j),
  ];
  final view = CatalogView.of(
    exercises: exercises,
    categories: categories,
    groups: groups,
    patterns: patterns,
  );

  test('ids are unique within each kind', () {
    for (final ids in [
      categories.map((e) => e.id),
      groups.map((e) => e.id),
      patterns.map((e) => e.id),
      exercises.map((e) => e.id),
      timers.map((e) => e.id),
    ]) {
      expect(ids.toSet().length, ids.length);
    }
  });

  test('names are unique per kind, ignoring case and accents', () {
    for (final names in [
      categories.map((e) => e.name),
      groups.map((e) => e.name),
      patterns.map((e) => e.name),
      exercises.map((e) => e.name),
      timers.map((e) => e.nombre),
    ]) {
      final normalized = names.map(normalizeName).toList();
      expect(normalized.toSet().length, normalized.length);
    }
  });

  test('every exercise passes validateExercise (references resolve, no cycles, only base items)', () {
    for (final e in exercises) {
      expect(validateExercise(e, view), isEmpty, reason: e.id);
      expect(scopeOf(e), CatalogScope.base);
    }
  });

  test('groups and patterns are flat and valid base nodes', () {
    final byId = {
      for (final n in [...groups, ...patterns]) n.id: n,
    };
    for (final n in byId.values) {
      expect(validateNode(n, byId), isEmpty, reason: n.id);
      expect(n.parentId, isNull);
    }
  });

  test('every exercise has categories, metrics and a default metric', () {
    for (final e in exercises) {
      expect(e.categoryIds, isNotEmpty, reason: e.id);
      expect(e.metrics, isNotEmpty, reason: e.id);
      expect(e.defaultMetric, isNotNull, reason: e.id);
    }
  });

  test(
    'every exercise has pattern and muscles, except the declared exceptions',
    () {
      for (final e in exercises) {
        if (_withoutMuscles.contains(e.id)) {
          expect(e.muscles, isEmpty, reason: e.id);
          continue;
        }
        expect(e.muscles, isNotEmpty, reason: e.id);
        expect(e.patternId, isNotNull, reason: e.id);
        expect(
          e.muscles.any((m) => m.weight == MuscleWeight.primary),
          isTrue,
          reason: e.id,
        );
        expect(
          e.muscles.map((m) => m.groupId).toSet().length,
          e.muscles.length,
          reason: '${e.id} repeats a group',
        );
      }
    },
  );

  test('without a load reference there is no percent-of-RM metric (explicit accessory)', () {
    for (final e in exercises) {
      final noSource =
          e.loadReference.kind != LoadReferenceKind.own &&
          e.loadReference.kind != LoadReferenceKind.otherExercise;
      if (noSource) {
        expect(e.metrics, isNot(contains(Metric.loadPctRm)), reason: e.id);
      }
    }
  });

  test(
    'every category, group and pattern is used by at least one exercise',
    () {
      expect(
        {for (final e in exercises) ...e.categoryIds},
        {for (final c in categories) c.id},
      );
      expect(
        {for (final e in exercises) ...e.muscles.map((m) => m.groupId)},
        {for (final g in groups) g.id},
      );
      expect({for (final e in exercises) e.patternId}.difference({null}), {
        for (final p in patterns) p.id,
      });
    },
  );

  test('WoDs are exactly the exercises of category wod, with a resolvable timer when they name one', () {
    final timerIds = {for (final t in timers) t.id};
    final rawEx = {
      for (final j in raw['ejercicios'] as List) (j as Map)['id']: j,
    };
    for (final e in exercises) {
      final isWod = e.categoryIds.contains('wod');
      expect(isWod, e.id.startsWith('wod_'), reason: e.id);
      if (isWod) {
        expect(e.categoryIds, ['wod'], reason: e.id);
        final t = rawEx[e.id]!['temporizadorId'];
        if (t != null) expect(timerIds, contains(t), reason: e.id);
      } else {
        expect(rawEx[e.id]!.containsKey('temporizadorId'), isFalse);
      }
    }
  });

  test('timers expand into phases', () {
    for (final t in timers) {
      expect(fasesDe(t), isNotEmpty, reason: t.id);
    }
  });
}
