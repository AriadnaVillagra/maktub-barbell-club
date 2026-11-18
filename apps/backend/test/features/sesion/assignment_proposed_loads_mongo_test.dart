import 'dart:io';

import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/assignment_proposed_loads/assignment_proposed_loads.dart';
import 'package:maktub_backend/features/sesion/assignment_proposed_loads/assignment_proposed_loads_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e714_${DateTime.now().microsecondsSinceEpoch}';
  final audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

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

  Future<void> insert(String collection, Json json) =>
      db!.collection(collection).insertOne(aDocumento(json));

  Reference rm(String clubId, String athleteId, String exerciseId) => Reference(
    id: 'rm-$clubId-$athleteId-$exerciseId',
    clubId: clubId,
    athleteId: athleteId,
    exerciseId: exerciseId,
    type: ReferenceType.rm,
    value: 100,
    date: DateTime.utc(2026, 11, 1),
    origin: ReferenceOrigin.values.first,
    auditoria: audit,
  );

  Future<void> seed(String clubId) async {
    await insert(
      Colecciones.asignaciones,
      Assignment(
        id: '$clubId-a1',
        clubId: clubId,
        planId: '$clubId-p1',
        members: [
          for (final a in ['ari', 'andi'])
            AssignmentMember(athleteId: a, from: DateTime.utc(2026, 11, 16)),
        ],
        groupId: '$clubId-g1',
        startDate: DateTime.utc(2026, 11, 16),
        status: AssignmentStatus.active,
        auditoria: audit,
      ).toJson(),
    );
    await insert(
      Colecciones.grupos,
      AthleteGroup(
        id: '$clubId-g1',
        clubId: clubId,
        name: 'g',
        memberIds: const ['ari', 'andi'],
        auditoria: audit,
      ).toJson(),
    );
    await insert(Colecciones.atletas, {
      'id': '$clubId-ari',
      'clubId': clubId,
      'usuarioId': 'user-ari',
    });
    await insert(
      Colecciones.planes,
      Plan(
        id: '$clubId-p1',
        clubId: clubId,
        name: 'p',
        weekModels: const [
          WeekModel(
            id: 'A',
            name: 'A',
            days: [
              PlanDay(
                blocks: [
                  PlanBlock(
                    name: 'x',
                    prescriptions: [
                      Prescription(
                        exerciseId: 'squat',
                        sets: [PlanSet(reps: 5, pct: 80)],
                      ),
                      Prescription(
                        exerciseId: 'curl',
                        sets: [PlanSet(reps: 10, kg: 8)],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        weekAssignment: const ['A', 'A', 'A', 'A'],
        published: PublishedPlan(
          weekModels: const [
            WeekModel(
              id: 'A',
              name: 'A',
              days: [
                PlanDay(
                  blocks: [
                    PlanBlock(
                      name: 'x',
                      prescriptions: [
                        Prescription(
                          exerciseId: 'squat',
                          sets: [PlanSet(reps: 5, pct: 80)],
                        ),
                        Prescription(
                          exerciseId: 'curl',
                          sets: [PlanSet(reps: 10, kg: 8)],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
          weekAssignment: const ['A', 'A', 'A', 'A'],
          publishedAt: DateTime.utc(2026, 11, 8),
          publishedBy: 'coach',
        ),
        auditoria: audit,
      ).toJson(),
    );
    for (final athleteId in ['ari', 'andi', 'luz']) {
      await insert(
        Colecciones.referencias,
        rm(clubId, athleteId, 'squat').toJson(),
      );
      await insert(
        Colecciones.factoresTrabajo,
        WorkFactor(
          id: 'f-$clubId-$athleteId',
          clubId: clubId,
          athleteId: athleteId,
          exerciseId: 'squat',
          value: 90,
          date: DateTime.utc(2026, 11, 2),
          auditoria: audit,
        ).toJson(),
      );
      await insert(
        Colecciones.kilajesFijos,
        FixedWeight(
          id: 'k-$clubId-$athleteId',
          clubId: clubId,
          athleteId: athleteId,
          exerciseId: 'curl',
          kg: 12,
          auditoria: audit,
        ).toJson(),
      );
    }
  }

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB not available');
        return;
      }
      await body();
    });
  }

  setUpAll(() async {
    if (db == null) return;
    for (final club in ['club-a', 'club-b']) {
      await seed(club);
    }
    await insert(
      Colecciones.ejercicios,
      Exercise(
        id: 'squat',
        clubId: clubPlataforma,
        name: 'squat',
        categoryIds: const ['primario'],
        metrics: const [Metric.loadPctRm],
        loadReference: const LoadReference.own(),
        auditoria: audit,
      ).toJson(),
    );
    await insert(
      Colecciones.ejercicios,
      Exercise(
        id: 'curl',
        clubId: 'club-a',
        name: 'curl',
        categoryIds: const ['accesorio'],
        metrics: const [Metric.loadPctRm],
        loadReference: const LoadReference.none(),
        auditoria: audit,
      ).toJson(),
    );
  });

  MongoAssignmentProposedLoadsStore store() =>
      MongoAssignmentProposedLoadsStore(db!);

  mongoTest(
    'reads only the club\'s assignment, athlete and plan',
    () async {
      expect(
        (await store().assignment('club-a', 'club-a-a1'))?.groupId,
        'club-a-g1',
      );
      expect(await store().assignment('club-a', 'club-b-a1'), isNull);
      expect(await store().athleteIdOfUser('club-b', 'user-ari'), 'club-b-ari');
      expect(await store().publishedPlan('club-a', 'club-a-p1'), isNotNull);
      expect(await store().publishedPlan('club-a', 'club-b-p1'), isNull);
    },
  );

  mongoTest('the catalog is the default one plus the club\'s', () async {
    expect(
      (await store().exercises('club-a')).keys,
      unorderedEquals(['squat', 'curl']),
    );
    expect((await store().exercises('club-b')).keys, ['squat']);
  });

  mongoTest(
    'references, factors and fixed weights of the athletes asked, in one club',
    () async {
      final athletes = {'ari', 'andi'};

      final references = await store().references('club-a', athletes, {
        'squat',
      });
      final factors = await store().workFactors('club-a', athletes, {'squat'});
      final fixed = await store().fixedWeights('club-a', athletes, {'curl'});

      expect([
        for (final r in references) r.athleteId,
      ], unorderedEquals(athletes));
      expect(references.every((r) => r.clubId == 'club-a'), isTrue);
      expect([for (final f in factors) f.athleteId], unorderedEquals(athletes));
      expect([for (final w in fixed) w.athleteId], unorderedEquals(athletes));
      expect(await store().references('club-a', athletes, {}), isEmpty);
      expect(await store().fixedWeights('club-a', {}, {'curl'}), isEmpty);
    },
  );

  mongoTest('the use case runs end to end and writes nothing', () async {
    final before = await db!.collection(Colecciones.sesiones).count();

    final dates = await AssignmentProposedLoads(store())(
      const ClubContext(
        clubId: 'club-a',
        userId: 'coach',
        roles: {Rol.coach},
        clubType: TipoClub.club,
      ),
      'club-a-a1',
      from: DateTime.utc(2026, 11, 16),
      to: DateTime.utc(2026, 11, 23),
      athleteIds: null,
      sessionAdjustment: null,
      exerciseAdjustments: const {},
    );

    expect(dates, hasLength(8));
    final athletes = dates.first.days.single.athletes;
    expect([for (final a in athletes) a.athleteId], ['ari', 'andi']);
    expect(athletes.first.sets.first.kg, isNotNull);
    expect(athletes.first.sets.first.workFactor, 90);
    expect(athletes.first.sets.last.kg, 12);
    expect(await db!.collection(Colecciones.sesiones).count(), before);
  });
}
