import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

/// The same answer for an athlete that is not in the club, one the user may not read, and a session the athlete
/// was not in, so it never says which of them exist.
const historyNotFound = ErrorDeSolicitud.noEncontrado('Historial no encontrado.');

/// Who reads an athlete's history, like the athlete sheet ("Quién lee perfiles"): whoever has
/// [Accion.verReportesDeTodos] (coach or club admin) reads any athlete of the club, and whoever has only
/// [Accion.verReportesPropios] reads the athlete linked to their own user. [linkedUserId] is the user of the
/// athlete asked for, or null when the club has no such athlete. Throws [historyNotFound] otherwise. The caller has
/// already authorized [Accion.verReportesPropios] (a 403 for a role without it).
void ensureCanReadHistory(ClubContext club, String? linkedUserId) {
  final allowed =
      linkedUserId != null &&
      (club.can(Accion.verReportesDeTodos) || linkedUserId == club.userId);
  if (!allowed) throw historyNotFound;
}

/// What the history needs of one set an athlete recorded: where it sits and how it was marked.
typedef RecordMark = ({SetPosition position, bool done, bool estimated});

RecordMark markOf(SetRecord r) => (
  position: (block: r.blockIndex, prescription: r.prescriptionIndex, set: r.setIndex),
  done: r.done,
  estimated: r.estimated,
);

/// The day [session] ran in the current published version of [plan]; null when the plan was deleted, never
/// published or no longer has that day. Sessions do not keep the version they ran, so the current one is used.
PlanDay? planDayOf(Session session, Plan? plan) =>
    plan?.published?.weekModelOf(session.week)?.days.elementAtOrNull(session.day - 1);

/// The history's summary of [session] for the athlete whose records are [marks].
///
/// `hechas` counts the positions marked done; `total` is the day's planned sets in the published plan plus any
/// recorded position the plan no longer has (so every set the detail shows is counted, and `hechas ≤ total`).
/// With an unchanged plan it matches the calendar's per-athlete progress.
HistoryEntry historyEntryOf(Session session, Plan? plan, Iterable<RecordMark> marks) {
  final day = planDayOf(session, plan);
  final planned = day == null ? const <SetPosition>{} : plannedSetPositions(day);
  return HistoryEntry(
    sessionId: session.id,
    date: session.date,
    assignmentId: session.assignmentId,
    planId: session.planId,
    planName: plan?.name,
    planType: plan?.type,
    cycle: session.cycle,
    week: session.week,
    day: session.day,
    dayName: day?.name,
    done: {for (final m in marks) if (m.done) m.position}.length,
    total: {...planned, for (final m in marks) m.position}.length,
    estimated: {for (final m in marks) if (m.estimated) m.position}.length,
  );
}
