import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// A day of an assignment that has sets recorded: where it sits in the cycle and the date of its session.
typedef DoneDay = ({int cycle, int week, int day, DateTime date});

/// One set an athlete recorded as done: the day it belongs to, the date of its session and its position in the day.
typedef DoneSet = ({
  int cycle,
  int week,
  int day,
  DateTime date,
  SetPosition position,
});

/// What the "status of each day" slice reads. Every method carries the club id.
abstract interface class DayStatusStore {
  /// Whether the group [groupId] exists in [clubId].
  Future<bool> groupExists(String clubId, String groupId);

  /// The active assignment of [groupId] in [clubId], or null if it has none.
  Future<Assignment?> activeAssignment(String clubId, String groupId);

  /// The assignment [assignmentId] of [clubId], whatever its owner and status, or null if the club has none.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// The published version of the plan [planId] of [clubId] (never the draft), or null if it has none.
  Future<PublishedPlan?> publishedPlan(String clubId, String planId);

  /// The days of the assignment, in any of [cycles], whose group session has at least one set recorded as done.
  /// A day can appear more than once if it was opened on several dates; callers treat it as done.
  Future<List<DoneDay>> doneDays(
    String clubId,
    String assignmentId,
    List<int> cycles,
  );

  /// The sets [athleteId] recorded as done in the sessions of the assignment, in any of [cycles]. The same position
  /// can appear more than once if its day was opened on several dates; callers count it once.
  Future<List<DoneSet>> doneSets(
    String clubId,
    String assignmentId,
    List<int> cycles,
    String athleteId,
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
  Future<Assignment?> assignment(String clubId, String assignmentId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
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

  @override
  Future<List<DoneSet>> doneSets(
    String clubId,
    String assignmentId,
    List<int> cycles,
    String athleteId,
  ) async {
    final docs = await _db.collection(Colecciones.sesiones).find({
      'clubId': clubId,
      'asignacionId': assignmentId,
      'ciclo': {r'$in': cycles},
    }).toList();
    if (docs.isEmpty) return const [];
    final sessions = <String, Session>{};
    for (final d in docs) {
      final s = Session.fromJson(desdeDocumento(d));
      sessions[s.id] = s;
    }
    final records = await _db.collection(Colecciones.registros).find(
      where
          .eq('clubId', clubId)
          .oneFrom('sesionId', sessions.keys.toList())
          .eq('atletaId', athleteId)
          .ne('hecha', false)
          .fields(['sesionId', 'bloque', 'prescripcion', 'serie']),
    ).toList();
    return [
      for (final r in records)
        if (sessions[r['sesionId']] case final s?)
          (
            cycle: s.cycle,
            week: s.week,
            day: s.day,
            date: s.date,
            position: (
              block: (r['bloque'] as num).toInt(),
              prescription: (r['prescripcion'] as num).toInt(),
              set: (r['serie'] as num).toInt(),
            ),
          ),
    ];
  }
}
