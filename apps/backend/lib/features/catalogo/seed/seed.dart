import 'dart:convert';

import 'package:maktub_backend/features/catalogo/seed/seed_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';

/// Author recorded in the audit of seeded documents (not a real user).
const seedAuthor = 'sistema:semilla';

/// The approved base list (`tool/semilla/catalogo_base.json`) as validated domain models, all with
/// `clubId` = `plataforma`.
class BaseCatalog {
  BaseCatalog._({
    required this.groups,
    required this.patterns,
    required this.categories,
    required this.exercises,
    required this.timers,
  });

  /// Builds and validates the list. Fields outside the model (`origen`) are dropped; `clubId`,
  /// `estado` and `auditoria` are set here. Throws [FormatException] listing every problem found.
  factory BaseCatalog.fromJson(Map<String, dynamic> raw, {required DateTime now}) {
    final audit = Auditoria.nueva(seedAuthor, ahora: now).toJson();
    List<Map<String, dynamic>> items(String key) => [
      for (final e in raw[key] as List)
        {
          for (final entry in (e as Map<String, dynamic>).entries)
            if (entry.key != 'origen') entry.key: entry.value,
          'clubId': clubPlataforma,
          'estado': CatalogStatus.active.cable,
          'auditoria': audit,
        },
    ];
    // Categories, groups and patterns have no `estado` of their own in the nodes' JSON: the
    // models ignore it, so only the ones that serialize it are affected.
    final catalog = BaseCatalog._(
      groups: [for (final j in items('gruposMusculares')) MuscleGroup.fromJson(j)],
      patterns: [for (final j in items('patrones')) MovementPattern.fromJson(j)],
      categories: [for (final j in items('categorias')) Category.fromJson(j)],
      exercises: [for (final j in items('ejercicios')) Exercise.fromJson(j)],
      timers: [for (final j in items('temporizadores')) Temporizador.fromJson(j)],
    );
    final problems = catalog.problems();
    if (problems.isNotEmpty) {
      throw FormatException('La lista base es inválida:\n${problems.join('\n')}');
    }
    return catalog;
  }

  final List<MuscleGroup> groups;
  final List<MovementPattern> patterns;
  final List<Category> categories;
  final List<Exercise> exercises;
  final List<Temporizador> timers;

  /// Every validation of E2.1 and E2.2 plus unique ids and names; empty if the list is sound.
  List<String> problems() {
    final out = <String>[];
    void unique<T>(String kind, Iterable<T> all, String Function(T) id, String Function(T) name) {
      final ids = all.map(id).toList();
      if (ids.toSet().length != ids.length) out.add('$kind: ids repetidos');
      final names = all.map((e) => normalizeName(name(e))).toList();
      if (names.toSet().length != names.length) out.add('$kind: nombres repetidos');
    }

    unique<MuscleGroup>('grupos', groups, (e) => e.id, (e) => e.name);
    unique<MovementPattern>('patrones', patterns, (e) => e.id, (e) => e.name);
    unique<Category>('categorías', categories, (e) => e.id, (e) => e.name);
    unique<Exercise>('ejercicios', exercises, (e) => e.id, (e) => e.name);
    unique<Temporizador>('temporizadores', timers, (e) => e.id, (e) => e.nombre);

    final view = CatalogView.of(
      exercises: exercises,
      categories: categories,
      groups: groups,
      patterns: patterns,
    );
    final nodes = {for (final n in [...groups, ...patterns]) n.id: n};
    for (final n in nodes.values) {
      for (final p in validateNode(n, nodes)) {
        out.add('${n.id}: $p');
      }
    }
    for (final e in exercises) {
      for (final p in validateExercise(e, view)) {
        out.add('${e.id}: $p');
      }
    }
    for (final t in timers) {
      for (final p in t.validar()) {
        out.add('${t.id}: $p');
      }
    }
    return out;
  }

  /// Insertion order: what exercises refer to goes first.
  List<SeedItem> get items => [
    for (final g in groups) SeedItem(Colecciones.gruposMusculares, g.id, 'grupo muscular ${g.name}', g.toJson()),
    for (final p in patterns) SeedItem(Colecciones.patrones, p.id, 'patrón ${p.name}', p.toJson()),
    for (final c in categories) SeedItem(Colecciones.categorias, c.id, 'categoría ${c.name}', c.toJson()),
    for (final e in exercises) SeedItem(Colecciones.ejercicios, e.id, 'ejercicio ${e.name}', e.toJson()),
    for (final t in timers) SeedItem(Colecciones.temporizadores, t.id, 'temporizador ${t.nombre}', t.toJson()),
  ];
}

class SeedItem {
  const SeedItem(this.collection, this.id, this.description, this.json);

  final String collection;
  final String id;
  final String description;
  final Json json;
}

/// What a run did, for the script's output.
class SeedResult {
  final created = <String>[];
  final existing = <String>[];

  /// Already there but different from the list: left as it is (see [BaseSeed]).
  final differing = <String>[];
}

/// Idempotent seed of the base catalog (design.md 3.5, F2, M1 5 task 2.4).
///
/// The natural key is the item's `id` (stable, so later corrections reach every club, M1-D5): a
/// document is inserted only if no base document with that id exists. **A re-run never overwrites**:
/// an existing document that differs from the list (ignoring `auditoria`) counts as "ya estaba" and
/// is also reported in [SeedResult.differing], because it may have been corrected on purpose through
/// the app. Fixing a base item is done there or by hand, not by re-seeding.
class BaseSeed {
  BaseSeed(this._store);

  final SeedStore _store;

  Future<SeedResult> run(BaseCatalog catalog) async {
    final result = SeedResult();
    final existing = <String, Map<String, Json>>{};
    for (final item in catalog.items) {
      final docs = existing[item.collection] ??= await _store.baseDocuments(item.collection);
      final current = docs[item.id];
      if (current == null) {
        await _store.insert(item.collection, item.json);
        result.created.add(item.description);
        continue;
      }
      result.existing.add(item.description);
      if (_canonical(_withoutAudit(current)) != _canonical(_withoutAudit(item.json))) {
        result.differing.add(item.description);
      }
    }
    return result;
  }

  static Json _withoutAudit(Json j) => {
    for (final e in j.entries)
      if (e.key != 'auditoria') e.key: e.value,
  };

  static String _canonical(Object? v) => jsonEncode(_sorted(v));

  static Object? _sorted(Object? v) {
    if (v is Map) {
      return {for (final k in (v.keys.map((k) => '$k').toList()..sort())) k: _sorted(v[k])};
    }
    if (v is List) return [for (final e in v) _sorted(e)];
    return v;
  }
}
