import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// A day of an assignment that has sets recorded: where it sits in the cycle and the date of its session.
typedef DoneDay = ({int cycle, int week, int day, DateTime date});

/// What the "status of each day" slice reads. Every method carries the club id.
abstract interface class DayStatusStore {
  /// Whether the group [groupId] exists in [clubId].
  Future<bool> groupExists(String clubId, String groupId);

  /// The active assignment of [groupId] in [clubId], or null if it has none.
  Future<Assignment?> activeAssignment(String clubId, String groupId);

  /// The published version of the plan [planId] of [clubId] (never the draft), or null if it has none.
  Future<PublishedPlan?> publishedPlan(String clubId, String planId);

  /// The days of the assignment, in any of [cycles], whose group session has at least one set recorded as done.
  /// A day can appear more than once if it was opened on several dates; callers treat it as done.
  Future<List<DoneDay>> doneDays(
    String clubId,
    String assignmentId,
    List<int> cycles,
  );
}

class MongoDayStatusStore implements DayStatusStore {
  MongoDayStatusStore(this._db);

  final Db _db;

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      await _db.collection(Colecciones.grupos).findOne({
        '_id': groupId,
        'clubId': clubId,
      }) !=
      null;

  @override
  Future<Assignment?> activeAssignment(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      'clubId': clubId,
      'grupoId': groupId,
      'estado': AssignmentStatus.active.cable,
    });
    return doc == null ? null : Assignment.fromJson(desdeDocumento(doc));
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
  Future<List<DoneDay>> doneDays(
    String clubId,
    String assignmentId,
    List<int> cycles,
  ) async {
    final docs = await _db.collection(Colecciones.sesiones).find({
      'clubId': clubId,
      'asignacionId': assignmentId,
      'ciclo': {r'$in': cycles},
    }).toList();
    if (docs.isEmpty) return const [];
    final sessions = [
      for (final d in docs) Session.fromJson(desdeDocumento(d)),
    ];
    final result = await _db.collection(Colecciones.registros).distinct(
      'sesionId',
      {
        'clubId': clubId,
        'sesionId': {
          r'$in': [for (final s in sessions) s.id],
        },
        'hecha': {r'$ne': false},
      },
    );
    final withSets = {for (final id in (result['values'] as List)) '$id'};
    return [
      for (final s in sessions)
        if (withSets.contains(s.id))
          (cycle: s.cycle, week: s.week, day: s.day, date: s.date),
    ];
  }
}
