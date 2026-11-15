import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/proposed_view.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'assignment_proposed_loads_store.dart';

/// Longest range a request may ask for, in days. The preload (E7.15) asks for 8.
const maxProposedLoadsRange = 31;

/// `GET /clubes/{clubId}/asignaciones/{asignacionId}/kilos-propuestos?desde=yyyy-MM-dd&hasta=yyyy-MM-dd
/// &atletaId=&ajuste=&ajusteEjercicio=` → 200 the kilos proposed for every set of every day of the plan, for each
/// date of the range and each athlete, without a session (E7.14, D8). Needs [Accion.registrar]. Writes nothing.
///
/// ```json
/// {"asignacionId": "a1", "fechas": [{"fecha": "2026-11-16", "ciclo": 1, "semana": 1, "dias": [
///   {"dia": 1, "atletas": [{"atletaId": "ari", "series": [ProposedSet]}]}]}]}
/// ```
///
/// - The date gives the cycle and the week, as opening the session does. The day is chosen when training (D13), so
///   every day of that week's model comes back. Kilos depend on the date because references and factors are
///   resolved on it.
/// - Each set is what `GET .../sesiones/{id}/atletas/{atletaId}/kilos-propuestos` gives for a session of that
///   assignment, date, week and day (same rule, `proposedDaySets`), with the same `ajuste` and `ajusteEjercicio`.
/// - `atletaId` (repeatable) picks athletes of the assignment's group; without it, the whole group (in a personal
///   club an athlete gets only themselves). The work factor only travels to whoever can edit references.
///
/// A coach can ask about any group of the club, an athlete only about their own (in a personal club, only about
/// themselves). 400 if a date or adjustment is malformed, `hasta` is before `desde` or the range is longer than
/// [maxProposedLoadsRange] days; 403 for a personal club asking about someone else; 404 if the assignment is not in
/// the club or is another group's for an athlete; 422 if an athlete is not in the group or the plan has no
/// published version. [store] is for tests.
Future<Response> assignmentProposedLoadsEndpoint(
  RequestContext context,
  String assignmentId, {
  AssignmentProposedLoadsStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final query = context.request.uri.queryParametersAll;
  final dates =
      await AssignmentProposedLoads(
        store ?? MongoAssignmentProposedLoadsStore(context.read<Db>()),
      )(
        club,
        assignmentId,
        from: fechaDeSolicitud(query['desde']?.last, 'desde'),
        to: fechaDeSolicitud(query['hasta']?.last, 'hasta'),
        athleteIds: query['atletaId'],
        sessionAdjustment: sessionAdjustmentParam(query['ajuste']),
        exerciseAdjustments: exerciseAdjustmentsParam(query['ajusteEjercicio']),
      );
  return Response.json(
    body: {
      'asignacionId': assignmentId,
      'fechas': [
        for (final date in dates)
          {
            'fecha': aIsoFecha(date.date),
            'ciclo': date.cycle,
            'semana': date.week,
            'dias': [
              for (final day in date.days)
                {
                  'dia': day.day,
                  'atletas': [
                    for (final athlete in day.athletes)
                      {
                        'atletaId': athlete.athleteId,
                        'series': [
                          for (final set in athlete.sets)
                            proposedSetForViewer(set, club),
                        ],
                      },
                  ],
                },
            ],
          },
      ],
    },
  );
}

/// The proposed kilos of one date of the range.
typedef ProposedDate = ({
  DateTime date,
  int cycle,
  int week,
  List<ProposedDay> days,
});

/// The proposed kilos of one day of the week's model (1-based [day]), per athlete.
typedef ProposedDay = ({
  int day,
  List<({String athleteId, List<ProposedSet> sets})> athletes,
});

class AssignmentProposedLoads {
  AssignmentProposedLoads(this._store);

  final AssignmentProposedLoadsStore _store;

  Future<List<ProposedDate>> call(
    ClubContext club,
    String assignmentId, {
    required DateTime from,
    required DateTime to,
    required List<String>? athleteIds,
    required int? sessionAdjustment,
    required Map<String, int> exerciseAdjustments,
  }) async {
    if (to.isBefore(from)) {
      throw const ErrorDeSolicitud('"hasta" no puede ser anterior a "desde".');
    }
    if (to.difference(from).inDays >= maxProposedLoadsRange) {
      throw const ErrorDeSolicitud(
        'El rango no puede pasar de $maxProposedLoadsRange días.',
      );
    }
    final clubId = club.clubId;
    final assignment = await _store.assignment(clubId, assignmentId);
    if (assignment == null) throw _assignmentNotFound;
    final members = await assignment.athletes(
      (groupId) => _store.groupMemberIds(clubId, groupId),
    );
    final athletes = await _athletes(club, members, athleteIds);
    final published = await _store.publishedPlan(clubId, assignment.planId);
    if (published == null) {
      throw const ErrorDeSolicitud(
        'El plan de la asignación no tiene una versión publicada.',
        estado: HttpStatus.unprocessableEntity,
      );
    }

    final dates = [
      for (var d = from; !d.isAfter(to); d = _nextDay(d))
        (
          date: d,
          location: UbicacionEnCiclo.desdeFechas(
            inicio: assignment.startDate,
            fecha: d,
          ),
        ),
    ];
    final weeks = {for (final d in dates) d.location.semana};
    final blocksByWeek = {
      for (final week in weeks)
        week: [
          for (
            var day = 1;
            day <= (published.weekModelOf(week)?.days.length ?? 0);
            day++
          )
            dayBlocks(published, week: week, day: day),
        ],
    };

    final exercises = await _store.exercises(clubId);
    final rmIds = <String, String?>{
      for (final days in blocksByWeek.values)
        for (final blocks in days) ...rmExerciseIdsOf(blocks, exercises),
    };
    final referenced = rmIds.values.whereType<String>().toSet();
    final athleteSet = athletes.toSet();
    final references = await _store.references(clubId, athleteSet, referenced);
    final factors = await _store.workFactors(clubId, athleteSet, referenced);
    final fixedKg = <String, Map<String, double>>{};
    for (final w in await _store.fixedWeights(
      clubId,
      athleteSet,
      rmIds.keys.toSet(),
    )) {
      (fixedKg[w.athleteId] ??= {})[w.exerciseId] = w.kg;
    }
    final equipo = await _store.equipment(clubId) ?? Equipo.estandarDe(clubId);

    return [
      for (final d in dates)
        (
          date: d.date,
          cycle: d.location.ciclo,
          week: d.location.semana,
          days: [
            for (final (i, blocks) in blocksByWeek[d.location.semana]!.indexed)
              (
                day: i + 1,
                athletes: [
                  for (final athleteId in athletes)
                    (
                      athleteId: athleteId,
                      sets: proposedDaySets(
                        blocks: blocks,
                        exercises: exercises,
                        athleteId: athleteId,
                        on: d.date,
                        references: references,
                        factors: factors,
                        fixedKg: fixedKg[athleteId] ?? const {},
                        equipo: equipo,
                        sessionAdjustment: sessionAdjustment,
                        exerciseAdjustments: exerciseAdjustments,
                      ),
                    ),
                ],
              ),
          ],
        ),
    ];
  }

  /// The athletes to propose for: [requested] or the whole group, after checking who may see them.
  Future<List<String>> _athletes(
    ClubContext club,
    List<String> members,
    List<String>? requested,
  ) async {
    String? own;
    if (!club.can(Accion.planificar)) {
      own = await _store.athleteIdOfUser(club.clubId, club.userId);
      if (own == null || !members.contains(own)) throw _assignmentNotFound;
    }
    final personal = own != null && club.clubType == TipoClub.personal;
    final athletes = requested == null || requested.isEmpty
        ? (personal ? [own] : members)
        : requested.toSet().toList();
    if (personal && athletes.any((id) => id != own)) throw forbiddenRole;
    if (!athletes.every(members.contains)) {
      throw const ErrorDeSolicitud(
        'Hay atletas que no son del grupo de la asignación.',
        estado: HttpStatus.unprocessableEntity,
      );
    }
    return athletes;
  }
}

const _assignmentNotFound = ErrorDeSolicitud.noEncontrado(
  'Asignación no encontrada.',
);

DateTime _nextDay(DateTime d) => DateTime.utc(d.year, d.month, d.day + 1);
