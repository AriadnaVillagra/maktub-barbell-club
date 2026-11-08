import 'dart:io';

import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/asignaciones/listar/listar_store.dart';
import 'package:maktub_backend/features/asignaciones/terminar/terminar_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e63_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base =
          Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
      await asegurarIndices(db!);
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
      await db!.collection(Colecciones.asignaciones).remove({});
      await body();
    });
  }

  var n = 0;
  Assignment assignment(
    String clubId,
    String groupId, {
    AssignmentStatus status = AssignmentStatus.active,
  }) => Assignment(
    id: 'a${n++}',
    clubId: clubId,
    planId: 'p1',
    groupId: groupId,
    startDate: DateTime.utc(2026, 11, 9),
    status: status,
    auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8)),
  );

  mongoTest(
    'the index is a unique partial index on active assignments',
    () async {
      final indexes = await db!
          .collection(Colecciones.asignaciones)
          .getIndexes();
      final index = indexes.firstWhere(
        (i) => i['name'] == 'club_grupo_activa_unica',
      );
      expect(index['unique'], isTrue);
      expect(index['partialFilterExpression'], {'estado': 'activa'});
      expect(index['key'], {'clubId': 1, 'grupoId': 1});
    },
  );

  mongoTest(
    'a second active assignment for the same group is refused',
    () async {
      final store = MongoCreateAssignmentStore(db!);

      expect(await store.insert(assignment('club-a', 'g1')), isTrue);
      expect(await store.insert(assignment('club-a', 'g1')), isFalse);
      expect(await db!.collection(Colecciones.asignaciones).count(), 1);
    },
  );

  mongoTest(
    'ended and paused ones do not count; other groups and clubs are free',
    () async {
      final store = MongoCreateAssignmentStore(db!);

      expect(
        await store.insert(
          assignment('club-a', 'g1', status: AssignmentStatus.ended),
        ),
        isTrue,
      );
      expect(
        await store.insert(
          assignment('club-a', 'g1', status: AssignmentStatus.ended),
        ),
        isTrue,
      );
      expect(
        await store.insert(
          assignment('club-a', 'g1', status: AssignmentStatus.paused),
        ),
        isTrue,
      );
      expect(await store.insert(assignment('club-a', 'g1')), isTrue);
      expect(await store.insert(assignment('club-a', 'g2')), isTrue);
      expect(await store.insert(assignment('club-b', 'g1')), isTrue);
      expect(await store.insert(assignment('club-a', 'g1')), isFalse);
    },
  );

  mongoTest(
    'two inserts at once for one group: exactly one succeeds',
    () async {
      final store = MongoCreateAssignmentStore(db!);
      final results = await Future.wait([
        for (var i = 0; i < 6; i++) store.insert(assignment('club-a', 'g1')),
      ]);

      expect(results.where((ok) => ok), hasLength(1));
      expect(await db!.collection(Colecciones.asignaciones).count(), 1);
    },
  );

  mongoTest(
    'ending frees the group; ending twice or in another club writes nothing',
    () async {
      final create = MongoCreateAssignmentStore(db!);
      final end = MongoEndAssignmentStore(db!);
      final first = assignment('club-a', 'g1');
      await create.insert(first);

      final at = DateTime.utc(2026, 11, 20, 10);
      expect(
        await end.end(
          'club-b',
          first.id,
          endDate: DateTime.utc(2026, 11, 20),
          userId: 'u',
          at: at,
        ),
        isFalse,
      );
      expect(
        (await end.assignment('club-a', first.id))!.status,
        AssignmentStatus.active,
      );

      expect(
        await end.end(
          'club-a',
          first.id,
          endDate: DateTime.utc(2026, 11, 20),
          userId: 'u2',
          at: at,
        ),
        isTrue,
      );
      final ended = (await end.assignment('club-a', first.id))!;
      expect(ended.status, AssignmentStatus.ended);
      expect(ended.endDate, DateTime.utc(2026, 11, 20));
      expect(ended.startDate, DateTime.utc(2026, 11, 9));
      expect(ended.auditoria.modificadoPor, 'u2');
      expect(ended.auditoria.creadoPor, 'coach');
      expect(
        await end.end(
          'club-a',
          first.id,
          endDate: DateTime.utc(2026, 11, 25),
          userId: 'u3',
          at: at,
        ),
        isFalse,
      );
      expect(
        (await end.assignment('club-a', first.id))!.endDate,
        DateTime.utc(2026, 11, 20),
      );

      expect(await create.insert(assignment('club-a', 'g1')), isTrue);
    },
  );

  mongoTest('publication and group checks only see the club', () async {
    final planes = db!.collection(Colecciones.planes);
    await planes.remove({});
    await planes.insertMany([
      {
        '_id': 'pub',
        'clubId': 'club-a',
        'publicado': {'asignacion': []},
      },
      {'_id': 'draft', 'clubId': 'club-a'},
    ]);
    await db!.collection(Colecciones.grupos).remove({});
    await db!.collection(Colecciones.grupos).insertOne({
      '_id': 'g1',
      'clubId': 'club-a',
    });
    final store = MongoCreateAssignmentStore(db!);

    expect(await store.planIsPublished('club-a', 'pub'), isTrue);
    expect(await store.planIsPublished('club-a', 'draft'), isFalse);
    expect(await store.planIsPublished('club-b', 'pub'), isNull);
    expect(await store.planIsPublished('club-a', 'zz'), isNull);
    expect(await store.groupExists('club-a', 'g1'), isTrue);
    expect(await store.groupExists('club-b', 'g1'), isFalse);
  });

  mongoTest('listing filters by club and optionally by group', () async {
    final create = MongoCreateAssignmentStore(db!);
    await create.insert(assignment('club-a', 'g1'));
    await create.insert(assignment('club-a', 'g2'));
    await create.insert(assignment('club-b', 'g1'));
    final list = MongoListAssignmentsStore(db!);

    expect(await list.assignments('club-a'), hasLength(2));
    expect(await list.assignments('club-a', groupId: 'g2'), hasLength(1));
    expect(await list.assignments('club-c'), isEmpty);
  });
}
