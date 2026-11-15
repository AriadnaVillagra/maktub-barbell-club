import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/import/athletes/athlete_import_store.dart';
import 'package:maktub_backend/features/import/athletes/athlete_plan.dart';
import 'package:maktub_backend/features/import/athletes/athlete_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje_store.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

/// Resolves a sheet exercise id (or basic lift key) to the app exercise, once the catalog is planned.
typedef ExerciseResolver = String? Function(String sheetId);

/// E8.3: Atletas, RMs and PesosAccesorios. Athletes are matched to the ones E1.9's alta created (never
/// created here); RMs go in through E3.2's [RegisterRm] and fixed weights through E3.3's [SetFixedWeight].
/// See [planAthleteImport] for the rules.
class AthleteImport implements ImportStep {
  AthleteImport({
    required this._reads,
    required this._exercises,
    required this._rmWrites,
    required this._weightWrites,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AthleteImportStore _reads;

  /// The catalog's resolver (`(await CatalogImport.plan(run)).exerciseIdFor`).
  final Future<ExerciseResolver> Function(ImportRun run) _exercises;
  final RegisterRmStore _rmWrites;
  final SetFixedWeightStore _weightWrites;
  final DateTime Function() _now;

  @override
  String get name => 'atletas';

  /// Reads the sheets and the club and decides what to do, without writing. E8.5 calls it to resolve the
  /// `atleta` column of Registro ([AthletePlan.athleteIdFor]).
  Future<AthletePlan> plan(ImportRun run) async {
    final sheets = AthleteSheets.read(
      athletes: run.sheets.read(AthleteSheetNames.athletes, columns: AthleteSheetNames.athleteColumns),
      rms: run.sheets.read(AthleteSheetNames.rms, columns: AthleteSheetNames.rmColumns),
      fixedWeights: run.sheets.read(AthleteSheetNames.fixedWeights, columns: AthleteSheetNames.fixedWeightColumns),
    );
    final clubId = run.club.clubId;
    final state = AthleteState(
      athletes: await _reads.athletes(clubId),
      rms: await _reads.rms(clubId),
      fixedWeights: await _reads.fixedWeights(clubId),
    );
    return planAthleteImport(
      sheets,
      state,
      clubId: clubId,
      exerciseIdFor: await _exercises(run),
      adjustments: athleteAdjustments(run),
      now: _now(),
    );
  }

  /// The `athletes` section of the adjustments file.
  static AthleteAdjustments athleteAdjustments(ImportRun run) =>
      AthleteAdjustments.fromJson((run.adjustments.raw['athletes'] as Map?)?.cast<String, dynamic>() ?? const {});

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (!run.dryRun) await apply(run.club, plan);
    return plan.report;
  }

  /// Carries out [plan]. A row the use case refuses (for instance, an exercise the catalog step has not
  /// written yet because it ran in a dry run) moves from created to problems; the rest go on.
  Future<void> apply(ClubContext club, AthletePlan plan) async {
    for (final p in plan.rmsToCreate) {
      final r = p.item;
      await _write(plan.report, p.label, () async {
        await RegisterRm(_rmWrites, newId: () => r.id, now: _now, origin: r.origin)(club, r.athleteId, {
          'ejercicioId': r.exerciseId,
          'valor': r.value,
          'fecha': aIsoFecha(r.date),
        });
      });
    }
    for (final p in plan.fixedWeightsToCreate) {
      final w = p.item;
      await _write(plan.report, p.label, () async {
        await SetFixedWeight(_weightWrites, newId: () => w.id, now: _now)(club, w.athleteId, {
          'ejercicioId': w.exerciseId,
          'kilos': w.kg,
        });
      });
    }
  }

  static Future<void> _write(ImportReport report, String label, Future<void> Function() write) async {
    try {
      await write();
    } on ErrorDeSolicitud catch (e) {
      report.created.remove(label);
      report.problems.add('$label: no se pudo escribir (${e.mensaje}).');
    }
  }
}
