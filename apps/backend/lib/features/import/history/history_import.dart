import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/import/athletes/athlete_sheets.dart';
import 'package:maktub_backend/features/import/history/history_import_store.dart';
import 'package:maktub_backend/features/import/history/history_plan.dart';
import 'package:maktub_backend/features/import/history/history_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/historic_plans.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';

/// E8.5: Registro and Tiempos into E7's sessions, set records and block times. See [planHistoryImport] for the
/// rules. Writes only through the E7 use cases: [OpenSession] (in history mode, which also opens sessions of
/// ended assignments), [RecordSet] (E7.3, one upsert per set) and [RecordBlockTime] (E7.19).
class HistoryImport implements ImportStep {
  HistoryImport({
    required this._sources,
    required this._reads,
    required this._sessionWrites,
    required this._setWrites,
    required this._timeWrites,
    LiveBroadcast? broadcast,
    DateTime Function()? now,
  }) : _broadcast = broadcast ?? MemoryLiveBroadcast(),
       _now = now ?? DateTime.now;

  /// What the earlier steps resolve (catalog, athletes, plans), built from their plans.
  final Future<HistorySources> Function(ImportRun run) _sources;
  final HistoryImportStore _reads;
  final OpenSessionStore _sessionWrites;
  final RecordSetStore _setWrites;
  final RecordBlockTimeStore _timeWrites;
  final LiveBroadcast _broadcast;
  final DateTime Function() _now;

  @override
  String get name => 'historial';

  /// Reads the sheets and the club and decides what to do, without writing.
  Future<HistoryPlan> plan(ImportRun run) async {
    final clubId = run.club.clubId;
    final sheets = HistorySheets.read(
      records: run.sheets.read(HistorySheetNames.records, columns: HistorySheetNames.recordColumns),
      times: run.sheets.read(HistorySheetNames.times, columns: HistorySheetNames.timeColumns),
    );
    final sources = await _sources(run);
    final sheetPlans = {
      for (final r in sheets.records)
        r.session.plan == legacyHistoryPlan ? historicPlanId(r.session.date) : r.session.plan,
      for (final t in sheets.times) t.session.plan,
    };
    final planIds = {for (final p in sheetPlans) ?sources.plans.planIdOf(p)};
    final assignments = await _reads.assignments(clubId, planIds);
    final sessions = await _reads.sessions(clubId, {for (final a in assignments) a.id});
    final sessionIds = {for (final s in sessions) s.id};
    final state = HistoryState(
      plans: await _reads.plans(clubId, planIds),
      assignments: assignments,
      groupMembers: await _reads.groupMembers(clubId, {for (final a in assignments) a.groupId}),
      sessions: sessions,
      records: await _reads.records(clubId, sessionIds),
      blockTimes: await _reads.blockTimes(clubId, sessionIds),
      fixedWeights: await _reads.fixedWeights(clubId),
    );
    final plan = planHistoryImport(sheets, sources, state, clubId: clubId);
    if (sources.pending.isNotEmpty) {
      plan.blocked = true;
      final steps = sources.pending.map((s) => '"$s"').join(', ');
      (run.dryRun ? plan.report.notes : plan.report.problems).add(
        run.dryRun
            ? 'Los pasos $steps tienen cambios sin aplicar: esto muestra el historial contra lo que hay hoy.'
            : 'Los pasos $steps tienen cambios sin aplicar: no se escribe nada del historial; corrélos antes.',
      );
    }
    return plan;
  }

  /// The sheet athlete ids and names of Atletas, for [HistorySources.sheetAthletes].
  static Map<String, String> sheetAthletes(ImportRun run) => {
    for (final row in run.sheets.read(AthleteSheetNames.athletes, columns: AthleteSheetNames.athleteColumns).rows)
      if (row['id'].isNotEmpty) row['id']: row['nombre'],
  };

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (run.dryRun) {
      _describe(plan);
    } else if (!plan.blocked) {
      await apply(run.club, plan);
    }
    return plan.report;
  }

  /// What a dry run would do, per session: new, with something to write, or all there.
  void _describe(HistoryPlan plan) {
    final report = plan.report;
    for (final s in plan.sessions) {
      final there = s.sets.where((p) => s.stored.containsKey(p.position)).length;
      final timesThere = s.times.where((t) => t.unchanged).length;
      final line =
          '${s.label}: ${s.sets.length} series${there > 0 ? ' ($there ya cargadas: se reescriben si cambian)' : ''}, '
          '${s.times.length} tiempos${timesThere > 0 ? ' ($timesThere ya cargados)' : ''}.';
      if (s.existing == null) {
        report.created.add(line);
      } else if (there == s.sets.length && timesThere == s.times.length) {
        report.unchanged.add(line);
      } else {
        report.updated.add(line);
      }
    }
  }

  /// Carries out [plan]. A session or row the use cases reject is reported and the others go on.
  Future<void> apply(ClubContext club, HistoryPlan plan) async {
    final report = plan.report;
    final now = _now;
    for (final s in plan.sessions) {
      final String sessionId;
      try {
        final opened = await OpenSession(_sessionWrites, _broadcast, newId: () => s.id, now: now, history: true)(
          club,
          s.openBody,
        );
        sessionId = opened.session.id;
      } on ErrorDeSolicitud catch (e) {
        report.problems.add(
          '${s.label}: no se pudo abrir la sesión (${e.estado}): ${e.mensaje}; sus ${s.sets.length} series y '
          '${s.times.length} tiempos no se importan.',
        );
        continue;
      }
      var written = 0, same = 0, timesWritten = 0;
      for (final p in s.sets) {
        try {
          final record = await RecordSet(_setWrites, _broadcast, newId: () => p.id, now: now)(club, sessionId, p.body);
          final before = s.stored[p.position];
          if (before != null && sameRecordContent(before, record)) {
            same++;
          } else {
            written++;
          }
          final rm = p.sheetRm;
          if (rm != null && record.referenceValue != rm) {
            report.notes.add(
              'Registro línea ${p.line}: la planilla tenía RM ${_fmt(rm)} y la app usa '
              '${record.referenceValue == null ? 'ninguno' : _fmt(record.referenceValue!)} '
              'en esa fecha.',
            );
          }
        } on ErrorDeSolicitud catch (e) {
          report.problems.add('Registro línea ${p.line}: no se pudo escribir (${e.estado}): ${e.mensaje}');
        }
      }
      for (final t in s.times) {
        if (t.unchanged) continue;
        try {
          await RecordBlockTime(_timeWrites, now: now)(club, sessionId, t.id, t.body);
          timesWritten++;
        } on ErrorDeSolicitud catch (e) {
          report.problems.add('Tiempos línea ${t.line}: no se pudo escribir (${e.estado}): ${e.mensaje}');
        }
      }
      final timesSame = s.times.where((t) => t.unchanged).length;
      final line =
          '${s.label}: $written series escritas, $same sin cambios; $timesWritten tiempos escritos, '
          '$timesSame sin cambios.';
      if (s.existing == null) {
        report.created.add(line);
      } else if (written > 0 || timesWritten > 0) {
        report.updated.add(line);
      } else {
        report.unchanged.add(line);
      }
    }
  }
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
