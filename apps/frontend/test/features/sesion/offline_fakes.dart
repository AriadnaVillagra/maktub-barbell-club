import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/domain/me.dart';
import 'package:maktub_frontend/features/access/domain/me_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_admin_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/proposed_days.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

import '../catalogo/catalog_fakes.dart';

/// Whether the fake server can be reached. Without signal every read fails as the API client reports it.
class Signal {
  bool on = true;

  void check() {
    if (!on) throw const ErrorDeApi('No se pudo conectar con el servidor.');
  }
}

final offlineStart = DateTime.utc(2026, 9, 1);

/// The server's plan: weeks 1 to 3 use model A, week 4 model B.
PublishedPlanView offlinePlan(String name) => PublishedPlanView(
  id: 'p1',
  name: name,
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 8, 30),
  weekAssignment: const ['A', 'A', 'A', 'B'],
  weekModels: const [
    WeekModel(
      id: 'A',
      name: 'Carga',
      days: [
        PlanDay(
          name: 'Piernas',
          blocks: [
            PlanBlock(
              name: 'Principal',
              categoryId: 'primario',
              prescriptions: [
                Prescription(
                  exerciseId: 'sq',
                  sets: [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)],
                ),
              ],
            ),
          ],
        ),
        PlanDay(name: 'Empuje'),
      ],
    ),
    WeekModel(
      id: 'B',
      name: 'Descarga',
      days: [
        PlanDay(name: 'Suave'),
        PlanDay(name: 'Movilidad'),
      ],
    ),
  ],
);

class OfflineMe implements MeRepository {
  OfflineMe(this.signal, this.me);

  final Signal signal;
  final Me me;
  int calls = 0;

  @override
  Future<Me> fetch() async {
    calls++;
    signal.check();
    return me;
  }
}

class OfflineGroups implements AssignmentRepository {
  OfflineGroups(this.signal);

  final Signal signal;

  @override
  Future<List<AthleteGroup>> groups(String clubId) async {
    signal.check();
    return [
      AthleteGroup(
        id: 'g1',
        clubId: clubId,
        name: 'Barra',
        memberIds: const ['ari', 'andi'],
        auditoria: audit(),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class OfflineCalendar implements CalendarRepository {
  OfflineCalendar(this.signal);

  final Signal signal;
  String planName = 'Fuerza';
  final located = <DateTime>[];

  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    signal.check();
    located.add(date);
    final where = UbicacionEnCiclo.desdeFechas(
      inicio: offlineStart,
      fecha: date,
    );
    return CalendarLocation(
      assignmentId: 'a1',
      planId: 'p1',
      startDate: offlineStart,
      cycle: where.ciclo,
      week: where.semana,
    );
  }

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async {
    signal.check();
    return offlinePlan(planName);
  }

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to,
  ) async {
    signal.check();
    final where = UbicacionEnCiclo.desdeFechas(
      inicio: offlineStart,
      fecha: from,
    );
    return [DayState(cycle: where.ciclo, week: 2, day: 1, done: true)];
  }
}

class OfflineCatalog implements CatalogRepository {
  OfflineCatalog(this.signal);

  final Signal signal;

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) async {
    signal.check();
    return [ex('sq', 'Sentadilla')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class OfflineCatalogAdmin implements CatalogAdminRepository {
  OfflineCatalogAdmin(this.signal);

  final Signal signal;

  @override
  Future<List<Temporizador>> timers(String clubId) async {
    signal.check();
    return const [];
  }

  @override
  Future<Equipo> team(String clubId) async {
    signal.check();
    return Equipo.estandarDe(clubId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class OfflineAthletes implements AthleteRepository {
  OfflineAthletes(this.signal);

  final Signal signal;

  @override
  Future<List<AthleteSummary>> athletes(String clubId) async {
    signal.check();
    return const [
      AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
      AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The kilos the preload brings: 82.5 for Ari and 62.5 for Andi on every set of every day.
List<ProposedSet> preloadedSets(String athleteId) => [
  for (var s = 0; s < 2; s++)
    ProposedSet(
      blockIndex: 0,
      prescriptionIndex: 0,
      setIndex: s,
      exerciseId: 'sq',
      kg: athleteId == 'ari' ? 82.5 : 62.5,
      appliedPct: 80,
    ),
];

class OfflineProposedDays implements ProposedDaysRepository {
  OfflineProposedDays(this.signal);

  final Signal signal;
  final ranges = <(DateTime, DateTime)>[];

  @override
  Future<List<ProposedDate>> proposedDays(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to,
  ) async {
    signal.check();
    ranges.add((from, to));
    return [
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
        () {
          final where = UbicacionEnCiclo.desdeFechas(
            inicio: offlineStart,
            fecha: d,
          );
          return ProposedDate(
            date: d,
            cycle: where.ciclo,
            week: where.semana,
            days: {
              for (var day = 1; day <= 2; day++)
                day: {
                  for (final a in ['ari', 'andi']) a: preloadedSets(a),
                },
            },
          );
        }(),
    ];
  }
}

/// The server's session: the kilos it resolves (90 for Ari, 70 for Andi, plus the adjustment's difference) differ
/// from the preloaded ones, so a test can tell which it shows.
class OfflineSessions implements SessionRepository {
  OfflineSessions(this.signal);

  final Signal signal;
  final opened = <(DateTime, int, int)>[];

  /// The session's guided pass (E7.26) and its last change number.
  GuidedPass? pass;
  var sessionChanges = 0;

  /// Every request taken, in order: `open <present>` and `set <session> <athlete> <set> <done>`.
  final log = <String>[];

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    signal.check();
    opened.add((date, week, day));
    log.add('open ${(presentAthleteIds.toList()..sort()).join(',')}');
    final where = UbicacionEnCiclo.desdeFechas(
      inicio: offlineStart,
      fecha: date,
    );
    return LiveSession(
      session: Session(
        id: 's1',
        clubId: clubId,
        assignmentId: assignmentId,
        planId: 'p1',
        cycle: where.ciclo,
        week: week,
        day: day,
        date: date,
        presentAthleteIds: presentAthleteIds.toList(),
        lastSessionChange: sessionChanges,
        guidedPass: pass,
        auditoria: audit(),
      ),
      records: const [],
    );
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    signal.check();
    final base = athleteId == 'ari' ? 90.0 : 70.0;
    return [
      for (var s = 0; s < 2; s++)
        ProposedSet(
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: s,
          exerciseId: 'sq',
          kg: base + adjustments.session - Ajuste.neutro,
          appliedPct: 80,
        ),
    ];
  }

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    signal.check();
    log.add(
      'set $sessionId ${write.athleteId} ${write.setIndex} ${write.done}',
    );
    return SetRecord(
      id: 'r-${write.setIndex}',
      clubId: clubId,
      sessionId: sessionId,
      athleteId: write.athleteId,
      exerciseId: 'sq',
      exerciseName: 'Sentadilla',
      blockIndex: write.blockIndex,
      prescriptionIndex: write.prescriptionIndex,
      setIndex: write.setIndex,
      target: const PlanSet(reps: 5, pct: 80),
      done: write.done,
      kg: write.manualKg ?? 90,
      reps: write.reps ?? 5,
      manualKg: write.manualKg != null,
      writtenBy: 'u1',
      auditoria: audit(),
    );
  }

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) async => signal.check();

  @override
  Future<Session> saveSessionNote(
    String clubId,
    String sessionId,
    String note,
  ) => throw UnimplementedError();

  @override
  Future<Session> writeGuidedPass(
    String clubId,
    String sessionId,
    GuidedPassAction action,
  ) async {
    signal.check();
    final next = applyGuidedAction(pass, action);
    if (next != null && !identical(next, pass)) {
      pass = next;
      sessionChanges++;
    }
    return Session(
      id: sessionId,
      clubId: clubId,
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 4,
      week: 1,
      day: 1,
      date: DateTime.utc(2026, 11, 24),
      lastSessionChange: sessionChanges,
      guidedPass: pass,
      auditoria: audit(),
    );
  }
}
