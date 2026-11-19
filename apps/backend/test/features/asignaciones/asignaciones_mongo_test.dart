import 'dart:io';

import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/asignaciones/listar/listar_store.dart';
import 'package:maktub_backend/features/asignaciones/set_athletes/set_athletes_store.dart';
import 'package:maktub_backend/features/asignaciones/terminar/terminar_store.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion_atleta/ubicacion_atleta_store.dart';
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
    String clubId, {
    List<String> athletes = const ['ari', 'andi'],
    AssignmentStatus status = AssignmentStatus.active,
  }) => Assignment(
    id: 'a${n++}',
    clubId: clubId,
    planId: 'p1',
    members: [
      for (final a in athletes)
        AssignmentMember(athleteId: a, from: DateTime.utc(2026, 11, 9)),
    ],
    startDate: DateTime.utc(2026, 11, 9),
    status: status,
    auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8)),
  );

  mongoTest('the D14 unique indexes are gone; the athlete index is there', () async {
    final names = [
      for (final i
          in await db!.collection(Colecciones.asignaciones).getIndexes())
        i['name'],
    ];
    expect(names, isNot(contains('club_grupo_activa_unica')));
    expect(names, isNot(contains('club_atleta_activa_unica')));
    expect(names, contains('club_atleta_estado'));
  });

  mongoTest(
    'an athlete can be in several active assignments, even of the same plan',
    () async {
      final store = MongoCreateAssignmentStore(db!);
      await store.insert(assignment('club-a'));
      await store.insert(assignment('club-a'));
      await store.insert(assignment('club-a', athletes: ['ari']));

      expect(await db!.collection(Colecciones.asignaciones).count(), 3);
      final list = MongoListAssignmentsStore(db!);
      expect(await list.assignments('club-a', athleteId: 'ari'), hasLength(3));
      expect(await list.assignments('club-a', athleteId: 'andi'), hasLength(2));
    },
  );

  mongoTest(
    'E6.7 migration: assignments without atletas get their group\'s or athlete\'s, once',
    () async {
      await db!.collection(Colecciones.grupos).remove({});
      await db!.collection(Colecciones.grupos).insertOne({
        '_id': 'g1',
        'clubId': 'club-a',
        'miembros': ['ari', 'andi'],
      });
      final audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));
      final collection = db!.collection(Colecciones.asignaciones);
      await collection.insertMany([
        {
          '_id': 'old-group',
          'clubId': 'club-a',
          'planId': 'p1',
          'grupoId': 'g1',
          'fechaInicio': '2026-11-02',
          'estado': 'activa',
          'auditoria': audit.toJson(),
        },
        {
          '_id': 'old-own',
          'clubId': 'club-a',
          'planId': 'p2',
          'atletaId': 'ari',
          'fechaInicio': '2026-11-06',
          'estado': 'terminada',
          'fechaFin': '2026-11-07',
          'auditoria': audit.toJson(),
        },
      ]);

      await copyAssignmentAthletes(db!);
      await copyAssignmentAthletes(db!);

      final group = (await collection.findOne({'_id': 'old-group'}))!;
      expect(group['atletas'], [
        {'atletaId': 'ari', 'desde': '2026-11-02'},
        {'atletaId': 'andi', 'desde': '2026-11-02'},
      ]);
      expect(group['grupoId'], 'g1');
      final own = (await collection.findOne({'_id': 'old-own'}))!;
      expect(own['atletas'], [
        {'atletaId': 'ari', 'desde': '2026-11-06'},
      ]);
      expect(own.containsKey('atletaId'), isFalse);
      final read = Assignment.fromJson(desdeDocumento(group));
      expect(read.currentAthleteIds, ['ari', 'andi']);
    },
  );

  mongoTest(
    "the athlete's location reads the club's active assignments they are in",
    () async {
      final create = MongoCreateAssignmentStore(db!);
      final both = assignment('club-a');
      final own = assignment('club-a', athletes: ['ari']);
      await create.insert(both);
      await create.insert(own);
      await create.insert(assignment('club-a', athletes: ['andi']));
      await create.insert(assignment('club-b', athletes: ['ari']));
      await create.insert(
        assignment('club-a', status: AssignmentStatus.ended),
      );
      final store = MongoAthleteLocationStore(db!);

      final active = await store.activeAssignments('club-a', 'ari');
      expect({for (final a in active) a.id}, {both.id, own.id});
      expect(await store.activeAssignments('club-a', 'x'), isEmpty);
    },
  );

  mongoTest('the athlete check only sees the club', () async {
    await db!.collection(Colecciones.atletas).remove({});
    await db!.collection(Colecciones.atletas).insertMany([
      {'_id': 'ari', 'clubId': 'club-a', 'usuarioId': 'u-ari'},
      {'_id': 'andi', 'clubId': 'club-a', 'usuarioId': 'u-andi'},
    ]);
    final store = MongoCreateAssignmentStore(db!);

    expect(await store.athletesExist('club-a', {'ari', 'andi'}), isTrue);
    expect(await store.athletesExist('club-a', {'ari', 'x'}), isFalse);
    expect(await store.athletesExist('club-b', {'ari'}), isFalse);
  });

  mongoTest(
    'setting the athletes writes only if nobody changed them, never on an ended one',
    () async {
      final create = MongoCreateAssignmentStore(db!);
      final set = MongoSetAssignmentAthletesStore(db!);
      final first = assignment('club-a');
      await create.insert(first);
      final at = DateTime.utc(2026, 11, 18, 10);
      final next = membersAfterChange(
        first.members,
        athleteIds: ['ari'],
        date: DateTime.utc(2026, 11, 18),
        startDate: first.startDate,
      );

      expect(
        await set.replaceMembers(first, next, userId: 'u2', at: at),
        isTrue,
      );
      final stored = (await set.assignment('club-a', first.id))!;
      expect(stored.currentAthleteIds, ['ari']);
      expect(stored.members.last.to, DateTime.utc(2026, 11, 17));
      expect(stored.auditoria.modificadoPor, 'u2');
      // A second write based on the old members loses.
      expect(
        await set.replaceMembers(first, first.members, userId: 'u3', at: at),
        isFalse,
      );
      expect(await set.assignment('club-b', first.id), isNull);

      await MongoEndAssignmentStore(db!).end(
        'club-a',
        first.id,
        endDate: DateTime.utc(2026, 11, 20),
        userId: 'u',
        at: at,
      );
      expect(
        await set.replaceMembers(stored, first.members, userId: 'u', at: at),
        isFalse,
      );
    },
  );

  mongoTest(
    'ending it twice or in another club writes nothing',
    () async {
      final create = MongoCreateAssignmentStore(db!);
      final end = MongoEndAssignmentStore(db!);
      final first = assignment('club-a');
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
      expect(ended.athleteIds, ['ari', 'andi']);
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
    },
  );

  mongoTest('publication and group checks only see the club', () async {
    final planes = db!.collection(Colecciones.planes);
    await planes.remove({});
    Map<String, dynamic> plan(String id, {bool published = false}) => aDocumento(
      Plan(
        id: id,
        clubId: 'club-a',
        name: id,
        published: published
            ? PublishedPlan(publishedAt: DateTime.utc(2026, 11), publishedBy: 'coach-1')
            : null,
        auditoria: Auditoria(creadoPor: 'coach-1', creadoEn: DateTime.utc(2026, 11)),
      ).toJson(),
    );
    await planes.insertMany([plan('pub', published: true), plan('draft')]);
    await db!.collection(Colecciones.grupos).remove({});
    await db!.collection(Colecciones.grupos).insertOne({
      '_id': 'g1',
      'clubId': 'club-a',
      'miembros': ['ari'],
    });
    final store = MongoCreateAssignmentStore(db!);

    expect((await store.plan('club-a', 'pub'))?.published, isNotNull);
    expect((await store.plan('club-a', 'draft'))?.published, isNull);
    expect(await store.plan('club-a', 'draft'), isNotNull);
    expect(await store.plan('club-b', 'pub'), isNull);
    expect(await store.plan('club-a', 'zz'), isNull);
    expect(await store.groupMemberIds('club-a', 'g1'), ['ari']);
    expect(await store.groupMemberIds('club-b', 'g1'), isNull);
  });

  mongoTest('listing filters by club and optionally by athlete', () async {
    final create = MongoCreateAssignmentStore(db!);
    await create.insert(assignment('club-a'));
    await create.insert(assignment('club-a', athletes: ['andi']));
    await create.insert(assignment('club-b'));
    final list = MongoListAssignmentsStore(db!);

    expect(await list.assignments('club-a'), hasLength(2));
    expect(await list.assignments('club-a', athleteId: 'ari'), hasLength(1));
    expect(await list.assignments('club-c'), isEmpty);
  });
}
