import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/catalogo/seed/seed.dart';
import 'package:maktub_backend/features/catalogo/seed/seed_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

class _FakeStore implements SeedStore {
  final data = <String, Map<String, Json>>{};

  int get total => data.values.fold(0, (n, c) => n + c.length);

  @override
  Future<Map<String, Json>> baseDocuments(String collection) async => Map.of(data[collection] ?? {});

  @override
  Future<void> insert(String collection, Json json) async {
    final col = data.putIfAbsent(collection, () => {});
    if (col.containsKey(json['id'])) throw StateError('duplicate ${json['id']}');
    col['${json['id']}'] = json;
  }
}

void main() {
  final raw = jsonDecode(File('tool/semilla/catalogo_base.json').readAsStringSync()) as Map<String, dynamic>;
  final now = DateTime.utc(2026, 11, 7);
  BaseCatalog build([Map<String, dynamic>? r]) => BaseCatalog.fromJson(r ?? raw, now: now);

  test('first run creates the whole approved list, all in plataforma and active', () async {
    final store = _FakeStore();
    final r = await BaseSeed(store).run(build());
    final catalog = build();
    expect(r.created, hasLength(catalog.items.length));
    expect(r.existing, isEmpty);
    expect(store.total, catalog.items.length);
    expect(store.data['ejercicios'], hasLength((raw['ejercicios'] as List).length));
    for (final col in store.data.values) {
      for (final d in col.values) {
        expect(d['clubId'], clubPlataforma);
        expect((d['auditoria'] as Map)['creadoPor'], seedAuthor);
        expect(d.containsKey('origen'), isFalse);
      }
    }
  });

  test('second run changes nothing and creates no duplicates', () async {
    final store = _FakeStore();
    await BaseSeed(store).run(build());
    final before = jsonEncode(store.data);
    // A later run has another clock: audit must not matter.
    final r = await BaseSeed(store).run(BaseCatalog.fromJson(raw, now: DateTime.utc(2027)));
    expect(r.created, isEmpty);
    expect(r.differing, isEmpty);
    expect(r.existing, hasLength(build().items.length));
    expect(jsonEncode(store.data), before);
  });

  test('an existing item that differs is kept as it is and reported', () async {
    final store = _FakeStore();
    await BaseSeed(store).run(build());
    store.data['ejercicios']!['sq_espalda']!['nombre'] = 'Corregido en la app';
    final r = await BaseSeed(store).run(build());
    expect(r.created, isEmpty);
    expect(r.differing, ['ejercicio Sentadilla de espalda']);
    expect(store.data['ejercicios']!['sq_espalda']!['nombre'], 'Corregido en la app');
  });

  test('inserts only what is missing', () async {
    final store = _FakeStore();
    await BaseSeed(store).run(build());
    store.data['temporizadores']!.remove('desc_90');
    final r = await BaseSeed(store).run(build());
    expect(r.created, ['temporizador Descanso 1:30']);
  });

  test('every exercise points at seeded groups, patterns and categories', () {
    final c = build();
    final groups = c.groups.map((e) => e.id).toSet();
    final patterns = c.patterns.map((e) => e.id).toSet();
    final cats = c.categories.map((e) => e.id).toSet();
    for (final e in c.exercises) {
      expect(cats.containsAll(e.categoryIds), isTrue, reason: e.id);
      expect(groups.containsAll(e.muscles.map((m) => m.groupId)), isTrue, reason: e.id);
      if (e.patternId != null) expect(patterns, contains(e.patternId), reason: e.id);
    }
  });

  test('an invalid document is rejected and nothing is written', () async {
    final bad = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    (bad['ejercicios'] as List).first['patronId'] = 'no_existe';
    expect(() => build(bad), throwsFormatException);

    final badTimer = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    (badTimer['temporizadores'] as List).first['trabajoSeg'] = 0;
    expect(() => build(badTimer), throwsFormatException);

    final dup = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    (dup['categorias'] as List).add((dup['categorias'] as List).first);
    expect(() => build(dup), throwsFormatException);
  });
}
