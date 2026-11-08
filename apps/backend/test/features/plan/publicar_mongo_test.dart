import 'dart:io';

import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e514_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base =
          Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
    } on Object catch (e) {
      stderr.writeln('mongo: $e');
      db = null;
    }
  });

  tearDownAll(() async {
    await db?.drop();
    await db?.close();
  });

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB not available');
        return;
      }
      await body();
    });
  }

  Plan plan(String clubId, {DateTime? modifiedAt, String blockName = 'Main'}) {
    final created = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));
    return Plan(
      id: 'p1',
      clubId: clubId,
      name: 'Plan',
      weekModels: [
        WeekModel(
          id: 'A',
          name: 'A',
          days: [
            PlanDay(blocks: [PlanBlock(name: blockName)]),
          ],
        ),
      ],
      weekAssignment: const ['A', 'A', 'A', 'A'],
      auditoria: modifiedAt == null
          ? created
          : created.modificada('coach', ahora: modifiedAt),
    );
  }

  PublishedPlan copy() => PublishedPlan(
    weekModels: plan('x').weekModels,
    weekAssignment: const ['A', 'A', 'A', 'A'],
    publishedAt: DateTime.utc(2026, 11, 8),
    publishedBy: 'coach',
  );

  Future<void> reset() => db!.collection(Colecciones.planes).remove({});
  Future<void> insert(Plan p) =>
      db!.collection(Colecciones.planes).insertOne(aDocumento(p.toJson()));

  mongoTest('publish writes the copy of the plan of that club only', () async {
    await reset();
    await insert(plan('club-a'));
    final store = MongoPublishPlanStore(db!);

    expect(await store.publish('club-b', 'p1', copy(), savedAt: null), isFalse);
    expect((await store.plan('club-a', 'p1'))!.published, isNull);

    expect(await store.publish('club-a', 'p1', copy(), savedAt: null), isTrue);
    final read = (await store.plan('club-a', 'p1'))!;
    expect(read.published!.toJson(), copy().toJson());
    expect(read.hasUnpublishedChanges, isFalse);
  });

  mongoTest(
    'publish does nothing if the plan was saved since it was read',
    () async {
      await reset();
      final saved = DateTime.utc(2026, 11, 5);
      await insert(plan('club-a', modifiedAt: saved));
      final store = MongoPublishPlanStore(db!);

      expect(
        await store.publish(
          'club-a',
          'p1',
          copy(),
          savedAt: DateTime.utc(2026, 11, 4),
        ),
        isFalse,
      );
      expect(
        await store.publish('club-a', 'p1', copy(), savedAt: null),
        isFalse,
      );
      expect((await store.plan('club-a', 'p1'))!.published, isNull);
      expect(
        await store.publish('club-a', 'p1', copy(), savedAt: saved),
        isTrue,
      );
    },
  );

  mongoTest('saving keeps the published copy stored in the document', () async {
    await reset();
    await insert(plan('club-a'));
    await MongoPublishPlanStore(db!)
        .publish('club-a', 'p1', copy(), savedAt: null);

    // A save built from a read taken before the publish carries no published copy.
    final edited = plan(
      'club-a',
      modifiedAt: DateTime.utc(2026, 11, 9),
      blockName: 'Edited',
    );
    expect(await MongoSavePlanStore(db!).replace(edited), isTrue);

    final read = (await MongoPublishPlanStore(db!).plan('club-a', 'p1'))!;
    expect(read.weekModels.single.days.single.blocks.single.name, 'Edited');
    expect(read.published!.toJson(), copy().toJson());
    expect(read.hasUnpublishedChanges, isTrue);
    expect(await MongoSavePlanStore(db!).replace(plan('club-b')), isFalse);
  });
}
