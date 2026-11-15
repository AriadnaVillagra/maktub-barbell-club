import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/import/assignments/assignment_import_store.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/historic_plans.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

/// One entry of `plans.assignments` in the adjustments: who did a sheet plan, and when. The sheet has no
/// assignments (Planes only says `activo` and `inicio`), so Ari decides them.
class AssignmentEntry {
  const AssignmentEntry({
    required this.plan,
    this.group,
    this.athlete,
    this.athleteIds,
    required this.from,
    required this.to,
  });

  factory AssignmentEntry.fromJson(Map<String, dynamic> j) => AssignmentEntry(
    plan: '${j['plan']}',
    group: j['group'] as String?,
    athlete: j['athlete'] as String?,
    from: desdeIsoFecha('${j['from']}'),
    to: desdeIsoFecha('${j['to']}'),
  );

  /// Sheet plan id.
  final String plan;

  /// Name of the club group that did it.
  final String? group;

  /// Display name of the one athlete that did it, for a plan of one person (E8.8): the assignment is theirs.
  final String? athlete;

  /// Club athlete ids that did it, for an entry derived from the rows (the history plans): the group is the
  /// smallest one that has them all.
  final Set<String>? athleteIds;
  final DateTime from;
  final DateTime to;

  String get label => 'asignación de $plan (${aIsoFecha(from)} a ${aIsoFecha(to)})';
}

/// The assignments of the history plans: each month, from its first to its last day, for the club athletes that
/// recorded in it ([athleteIdFor] resolves sheet athlete ids; an unresolved one is left out, and the history step
/// reports its rows).
List<AssignmentEntry> historicAssignments(HistoricPlans historic, String? Function(String sheetId) athleteIdFor) => [
  for (final plan in historic.plans)
    if ({for (final a in historic.athletes[plan.id] ?? const <String>{}) ?athleteIdFor(a)} case final ids
        when ids.isNotEmpty)
      AssignmentEntry(
        plan: plan.id,
        athleteIds: ids,
        from: desdeIsoFecha(plan.start!),
        to: DateTime.utc(desdeIsoFecha(plan.start!).year, desdeIsoFecha(plan.start!).month + 1, 0),
      ),
];

/// The `plans.assignments` section of `tool/importar/ajustes.json`.
List<AssignmentEntry> assignmentAdjustments(Map<String, dynamic> raw) => [
  for (final e in ((raw['plans'] as Map?)?['assignments'] as List? ?? const []))
    AssignmentEntry.fromJson((e as Map).cast<String, dynamic>()),
];

/// An assignment to create, with the body of E6's create use case.
class PlannedAssignment {
  const PlannedAssignment({required this.id, required this.body, required this.label});

  final String id;
  final Json body;
  final String label;
}

/// What the assignments import has to do.
class AssignmentPlan {
  AssignmentPlan._() : report = ImportReport('Asignaciones');

  final ImportReport report;
  final toCreate = <PlannedAssignment>[];

  bool get isEmpty => toCreate.isEmpty;
}

/// What the club has today, the input of [planAssignmentImport].
class AssignmentState {
  const AssignmentState({
    this.groups = const [],
    this.athletes = const [],
    this.plans = const {},
    this.publishedPlans = const {},
    this.assignments = const {},
  });

  final List<AthleteGroup> groups;

  /// The club athletes, for an entry of one athlete.
  final List<Atleta> athletes;
  final Set<String> plans;
  final Set<String> publishedPlans;

  /// The assignments the entries would create, by id, if they already exist.
  final Map<String, Assignment> assignments;
}

/// The stable id of the assignment of [entry]: [importedId] of the sheet plan and the start date.
String assignmentImportId(String clubId, AssignmentEntry entry) =>
    importedId(clubId, 'asignacion-${entry.plan}-${aIsoFecha(entry.from)}');

/// Decides, entry by entry (pure, no I/O). Each entry becomes an **ended** assignment of the plan imported in E8.4
/// (`from` to `to`), so D14 (one active assignment per owner) is never touched. Rules:
/// - The group is found by name in the club. An entry for one athlete (`athlete`, E8.8) becomes that athlete's own
///   assignment; the athlete is found by display name in the club.
/// - The plan must be imported and published (E6 assigns only published plans); a draft is reported.
/// - An assignment that already exists with that id is left alone: unchanged if it says the same, else differing.
AssignmentPlan planAssignmentImport(List<AssignmentEntry> entries, AssignmentState state, {required String clubId}) {
  final out = AssignmentPlan._();
  final report = out.report;
  for (final e in entries) {
    final ids = e.athleteIds;
    if (e.group == null && ids != null) {
      final candidates = state.groups.where((g) => g.memberIds.toSet().containsAll(ids)).toList()
        ..sort((a, b) => a.memberIds.length.compareTo(b.memberIds.length));
      final smallest = candidates.where((g) => g.memberIds.length == candidates.firstOrNull?.memberIds.length);
      if (smallest.length != 1) {
        report.problems.add(
          '${e.label}: ${smallest.isEmpty ? 'ningún grupo tiene a todos los atletas que registraron' : 'hay '
                    '${smallest.length} grupos igual de chicos con todos los atletas que registraron'}; queda sin asignar.',
        );
        continue;
      }
      _plan(out, e, _Owner.group(smallest.single), state, clubId);
      continue;
    }
    if (e.group == null && e.athlete != null) {
      final wanted = e.athlete!.trim().toLowerCase();
      final athletes = state.athletes.where((a) => a.nombreVisible.trim().toLowerCase() == wanted).toList();
      if (athletes.length != 1) {
        report.problems.add(
          '${e.label}: ${athletes.isEmpty ? 'no hay un atleta "${e.athlete}"' : 'hay ${athletes.length} atletas '
                    '"${e.athlete}"'} en el club.',
        );
        continue;
      }
      _plan(out, e, _Owner.athlete(athletes.single), state, clubId);
      continue;
    }
    if (e.group == null) {
      report.problems.add('${e.label}: no dice de qué grupo ni de qué atleta es; queda sin asignar.');
      continue;
    }
    final groups = state.groups.where((g) => g.name.trim().toLowerCase() == e.group!.trim().toLowerCase()).toList();
    if (groups.length != 1) {
      report.problems.add(
        '${e.label}: ${groups.isEmpty ? 'no hay un grupo "${e.group}"' : 'hay ${groups.length} grupos "${e.group}"'} '
        'en el club.',
      );
      continue;
    }
    _plan(out, e, _Owner.group(groups.single), state, clubId);
  }
  return out;
}

/// Who an entry's assignment is for: a club group or one club athlete.
class _Owner {
  _Owner.group(AthleteGroup g) : groupId = g.id, athleteId = null, label = 'grupo "${g.name}"';
  _Owner.athlete(Atleta a) : groupId = null, athleteId = a.id, label = 'atleta "${a.nombreVisible}"';

  final String? groupId;
  final String? athleteId;
  final String label;
}

void _plan(AssignmentPlan out, AssignmentEntry e, _Owner owner, AssignmentState state, String clubId) {
  final report = out.report;
  if (e.to.isBefore(e.from)) {
    report.problems.add('${e.label}: termina antes de empezar.');
    return;
  }
  final planId = importedId(clubId, e.plan);
  if (!state.plans.contains(planId)) {
    report.problems.add('${e.label}: el plan no está importado (paso planes).');
    return;
  }
  if (!state.publishedPlans.contains(planId)) {
    report.problems.add(
      '${e.label}: el plan está en borrador y E6 solo asigna planes publicados; se asigna cuando se publique '
      '(plans.pctFills).',
    );
    return;
  }
  final id = assignmentImportId(clubId, e);
  final label = '${e.label}, ${owner.label}';
  final stored = state.assignments[id];
  if (stored == null) {
    out.toCreate.add(
      PlannedAssignment(
        id: id,
        label: label,
        body: {
          'planId': planId,
          'grupoId': ?owner.groupId,
          'atletaId': ?owner.athleteId,
          'fechaInicio': aIsoFecha(e.from),
          'fechaFin': aIsoFecha(e.to),
        },
      ),
    );
    report.created.add('$label: terminada.');
  } else if (stored.planId == planId &&
      stored.groupId == owner.groupId &&
      stored.athleteId == owner.athleteId &&
      stored.startDate == e.from &&
      stored.endDate == e.to &&
      stored.status == AssignmentStatus.ended) {
    report.unchanged.add(label);
  } else {
    report.differing.add('$label: ya existe y no coincide (${e.athleteIds == null ? 'ajustes.json' : 'Registro'}).');
  }
}

/// E8.5: the assignments of the imported plans, which the sheet does not have (`plans.assignments` in the
/// adjustments, or derived from Registro for the history plans). Writes only through E6's [CreateAssignment], in
/// history mode (created already ended).
class AssignmentImport implements ImportStep {
  AssignmentImport({required this._reads, required this._writes, this._derived, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AssignmentImportStore _reads;

  /// Entries that follow from the data instead of the adjustments (the history plans: who recorded in each month).
  /// An entry of `plans.assignments` for the same plan wins.
  final Future<List<AssignmentEntry>> Function(ImportRun run)? _derived;
  final CreateAssignmentStore _writes;
  final DateTime Function() _now;

  @override
  String get name => 'asignaciones';

  /// Reads the adjustments and the club and decides what to do, without writing.
  Future<AssignmentPlan> plan(ImportRun run) async {
    final clubId = run.club.clubId;
    final explicit = assignmentAdjustments(run.adjustments.raw);
    final entries = [
      ...explicit,
      for (final e in await _derived?.call(run) ?? const <AssignmentEntry>[])
        if (!explicit.any((x) => x.plan == e.plan)) e,
    ];
    final planIds = {for (final e in entries) importedId(clubId, e.plan)};
    final state = AssignmentState(
      groups: await _reads.groups(clubId),
      athletes: await _reads.athletes(clubId),
      plans: await _reads.planIds(clubId, planIds),
      publishedPlans: await _reads.publishedPlanIds(clubId, planIds),
      assignments: await _reads.assignments(clubId, {for (final e in entries) assignmentImportId(clubId, e)}),
    );
    return planAssignmentImport(entries, state, clubId: clubId);
  }

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (!run.dryRun) await apply(run.club, plan);
    return plan.report;
  }

  Future<void> apply(ClubContext club, AssignmentPlan plan) async {
    for (final a in plan.toCreate) {
      try {
        await CreateAssignment(_writes, newId: () => a.id, now: _now, history: true)(club, a.body);
      } on ErrorDeSolicitud catch (e) {
        plan.report.created.remove('${a.label}: terminada.');
        plan.report.problems.add('${a.label}: no se pudo escribir (${e.estado}): ${e.mensaje}');
      }
    }
  }
}
