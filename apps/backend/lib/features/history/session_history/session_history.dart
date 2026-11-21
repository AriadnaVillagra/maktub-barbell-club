import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/history/history_view.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'session_history_store.dart';

/// `GET /clubes/{clubId}/atletas/{athleteId}/historial/{sesionId}` → 200 [SessionHistory]: `{"sesion":
/// HistoryEntry, "nota"?, "bloques": [{"bloque", "nombre"?, "segundos"?, "interrumpido"?, "ejercicios":
/// [{"prescripcion", "ejercicioId", "ejercicioNombre", "series": [{"serie", "objetivo", "registro"?}]}]}]}`.
///
/// The day's structure comes from the plan's current published version (a session does not keep the version it
/// ran), merged with the athlete's records: a planned set without a record comes with the plan's target and no
/// `registro`; a record keeps its own target, exercise and name, even where the plan changed since, and one the plan
/// no longer has still shows at its position. With the plan deleted (E8.9) only the records and block times are
/// left. Exercise names are the recorded ones, or the catalog's for exercises with nothing recorded. Block times
/// are the athlete's runs of each block in the guided mode, added up. A record travels without the work factor and
/// real percent for whoever cannot see work factors (see [recordForViewer]); a target keeps only this athlete's
/// frozen load (E5.16).
///
/// Access: see [ensureCanReadHistory]. 404 as well when the session is not in the club or the athlete was not in
/// it. Read-only. [store] is for tests.
Future<Response> sessionHistoryEndpoint(
  RequestContext context,
  String athleteId,
  String sessionId, {
  SessionHistoryStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verReportesPropios);
  final history = await ReadSessionHistory(
    store ?? MongoSessionHistoryStore(context.read<Db>()),
  )(club, athleteId, sessionId);
  return Response.json(body: history.toJson());
}

class ReadSessionHistory {
  ReadSessionHistory(this._store);

  final SessionHistoryStore _store;

  Future<SessionHistory> call(ClubContext club, String athleteId, String sessionId) async {
    ensureCanReadHistory(club, await _store.athleteUserId(club.clubId, athleteId));
    final session = await _store.session(club.clubId, sessionId);
    if (session == null || !session.presentAthleteIds.contains(athleteId)) throw historyNotFound;

    final plan = await _store.plan(club.clubId, session.planId);
    final records = [
      for (final r in await _store.records(club.clubId, sessionId, athleteId))
        SetRecord.fromJson(recordForViewer(r, club)),
    ];
    final times = await _store.blockTimes(club.clubId, sessionId, athleteId);
    final builder = _BlocksBuilder(athleteId)
      ..addPlan(planDayOf(session, plan))
      ..addRecords(records)
      ..addTimes(times);
    final names = await _store.exerciseNames(club.clubId, builder.unnamedExercises());
    return SessionHistory(
      entry: historyEntryOf(session, plan, records.map(markOf)),
      note: session.note,
      blocks: builder.build(names),
    );
  }
}

class _Set {
  _Set(this.target);

  PlanSet target;
  SetRecord? record;
}

class _Exercise {
  _Exercise(this.exerciseId);

  String exerciseId;
  String? recordedName;
  final sets = <int, _Set>{};
}

class _Block {
  String? timeName;
  int? seconds;
  bool interrupted = false;
  final exercises = <int, _Exercise>{};
}

/// Puts the plan's day, the records and the block times together by position.
class _BlocksBuilder {
  _BlocksBuilder(this._athleteId);

  final String _athleteId;
  final _blocks = <int, _Block>{};

  _Block _block(int index) => _blocks[index] ??= _Block();

  /// Block names of the published plan's day, by position. Blocks without exercises count too: a guided run
  /// may have left a time for them.
  final _planNames = <int, String>{};

  void addPlan(PlanDay? day) {
    if (day == null) return;
    for (final (b, block) in day.blocks.indexed) {
      _planNames[b] = block.name;
      for (final (p, prescription) in block.prescriptions.indexed) {
        final exerciseId = prescription.exerciseId;
        if (exerciseId == null) continue;
        final exercise = _block(b).exercises[p] ??= _Exercise(exerciseId);
        for (final (s, set) in prescription.sets.indexed) {
          exercise.sets[s] = _Set(_ownTarget(set));
        }
      }
    }
  }

  void addRecords(List<SetRecord> records) {
    for (final r in records) {
      final exercise = _block(r.blockIndex).exercises[r.prescriptionIndex] ??= _Exercise(r.exerciseId);
      // What was recorded wins over a plan changed since.
      exercise.exerciseId = r.exerciseId;
      if (r.exerciseName.trim().isNotEmpty) exercise.recordedName = r.exerciseName;
      (exercise.sets[r.setIndex] ??= _Set(_ownTarget(r.target)))
        ..target = _ownTarget(r.target)
        ..record = r;
    }
  }

  void addTimes(List<BlockTime> times) {
    for (final t in times) {
      if (!t.athleteIds.contains(_athleteId)) continue;
      final block = _block(t.blockIndex);
      block.seconds = (block.seconds ?? 0) + (t.seconds < 0 ? 0 : t.seconds);
      block.interrupted = block.interrupted || t.interrupted;
      if (t.blockName.trim().isNotEmpty) block.timeName ??= t.blockName;
    }
  }

  /// Exercises with no recorded name, whose name comes from the catalog.
  Set<String> unnamedExercises() => {
    for (final block in _blocks.values)
      for (final e in block.exercises.values)
        if (e.recordedName == null) e.exerciseId,
  };

  List<HistoryBlock> build(Map<String, String> catalogNames) {
    List<int> sorted(Iterable<int> keys) => keys.toList()..sort();
    return [
      for (final b in sorted(_blocks.keys))
        if (_blocks[b]! case final block)
          HistoryBlock(
            index: b,
            name: _nonEmpty(_planNames[b]) ?? _nonEmpty(block.timeName),
            seconds: block.seconds,
            interrupted: block.interrupted,
            exercises: [
              for (final p in sorted(block.exercises.keys))
                if (block.exercises[p]! case final e)
                  HistoryExercise(
                    index: p,
                    exerciseId: e.exerciseId,
                    exerciseName: e.recordedName ?? catalogNames[e.exerciseId] ?? '',
                    sets: [
                      for (final s in sorted(e.sets.keys))
                        HistorySet(index: s, target: e.sets[s]!.target, record: e.sets[s]!.record),
                    ],
                  ),
            ],
          ),
    ];
  }

  /// [set] keeping only this athlete's frozen load: the others' are not this history's.
  PlanSet _ownTarget(PlanSet set) {
    if (set.byAthlete.isEmpty) return set;
    final json = set.toJson()..remove('porAtleta');
    final own = set.byAthlete[_athleteId];
    if (own != null) json['porAtleta'] = {_athleteId: own.toJson()};
    return PlanSet.fromJson(json);
  }
}

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s;
