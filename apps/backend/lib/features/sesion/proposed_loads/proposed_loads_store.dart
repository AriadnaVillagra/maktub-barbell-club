import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "proposed kilos" slice reads. Every method carries the club id.
abstract interface class ProposedLoadsStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The assignment [assignmentId] of [clubId], or null.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// The athlete ids of the group [groupId] of [clubId]; empty if the group is not in the club.
  Future<List<String>> groupMemberIds(String clubId, String groupId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The published version of the plan [planId] of [clubId] (never the draft), or null if it has none.
  Future<PublishedPlan?> publishedPlan(String clubId, String planId);

  /// The exercises [clubId] can see, by id: the default catalog and its own. Archived ones included.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// The RMs and other references of [athleteId] for [exerciseIds] (the full history).
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  );

  /// The work factors of [athleteId] for [exerciseIds] (the full history).
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  );

  /// The fixed weights of [athleteId] for [exerciseIds], by exercise id.
  Future<Map<String, FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  );

  /// The club's equipment, or null if it never saved one.
  Future<Equipo?> equipment(String clubId);
}

class MongoProposedLoadsStore implements ProposedLoadsStore {
  MongoProposedLoadsStore(this._db);

  final Db _db;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
    });
    return doc == null ? null : Assignment.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.grupos).findOne({
      '_id': groupId,
      'clubId': clubId,
    });
    return doc == null
        ? const []
        : AthleteGroup.fromJson(desdeDocumento(doc)).memberIds;
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc)).published;
  }

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async {
    final docs = await _db.collection(Colecciones.ejercicios).find({
      'clubId': {
        r'$in': [clubPlataforma, clubId],
      },
    }).toList();
    return {
      for (final d in docs)
        '${d['_id']}': Exercise.fromJson(desdeDocumento(d)),
    };
  }

  Future<List<Json>> _ofExercises(
    String collection,
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) return const [];
    final docs = await _db.collection(collection).find({
      'clubId': clubId,
      'atletaId': athleteId,
      'ejercicioId': {r'$in': exerciseIds.toList()},
    }).toList();
    return [for (final d in docs) desdeDocumento(d)];
  }

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => [
    for (final j in await _ofExercises(
      Colecciones.referencias,
      clubId,
      athleteId,
      exerciseIds,
    ))
      Reference.fromJson(j),
  ];

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => [
    for (final j in await _ofExercises(
      Colecciones.factoresTrabajo,
      clubId,
      athleteId,
      exerciseIds,
    ))
      WorkFactor.fromJson(j),
  ];

  @override
  Future<Map<String, FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async {
    final weights = [
      for (final j in await _ofExercises(
        Colecciones.kilajesFijos,
        clubId,
        athleteId,
        exerciseIds,
      ))
        FixedWeight.fromJson(j),
    ];
    return {for (final w in weights) w.exerciseId: w};
  }

  @override
  Future<Equipo?> equipment(String clubId) async {
    final doc = await _db.collection(Colecciones.equipos).findOne({
      '_id': clubId,
      'clubId': clubId,
    });
    return doc == null ? null : Equipo.fromJson(desdeDocumento(doc));
  }
}
