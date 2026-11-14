import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_timers.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';
import 'package:maktub_frontend/features/temporizador/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';
import '../temporizador/timer_fakes.dart';

final _today = DateTime.utc(2026, 11, 18);
final _start = DateTime.utc(2026, 9, 1);

final _timers = [
  timer('rest90', 'Descanso 90', work: 90),
  timer('rest60', 'Descanso 60', work: 60),
  timer(
    'tabata',
    'Tabata',
    type: TipoTemporizador.tabata,
    work: 20,
    rest: 10,
    rounds: 8,
  ),
  timer('amrap', 'AMRAP 12', type: TipoTemporizador.amrap, work: 720),
  timer('old', 'Descanso viejo', work: 45, status: CatalogStatus.archived),
];

Prescription _prescription({String? timerId}) => Prescription(
  exerciseId: 'sq',
  timerId: timerId,
  sets: const [PlanSet(reps: 5, pct: 80)],
);

final _plan = PublishedPlanView(
  id: 'p1',
  name: 'Fuerza',
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 11, 1),
  weekAssignment: const ['A', 'A', 'A', 'A'],
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'Carga',
      days: [
        PlanDay(
          name: 'Piernas',
          blocks: [
            // 0: the prescription's own timer.
            PlanBlock(
              name: 'Principal',
              categoryId: 'primario',
              prescriptions: [_prescription(timerId: 'rest90')],
            ),
            // 1: the block's default rest, and a prescription that overrides it.
            PlanBlock(
              name: 'Accesorios',
              categoryId: 'accesorio',
              timerId: 'rest60',
              prescriptions: [
                _prescription(),
                _prescription(timerId: 'tabata'),
              ],
            ),
            // 2: a timed block's timer is the WoD's, not a rest.
            PlanBlock(
              name: 'WoD',
              categoryId: 'wod',
              executionMode: ExecutionMode.timed,
              timerId: 'amrap',
              prescriptions: [_prescription()],
            ),
            // 3: no timer at all.
            PlanBlock(
              name: 'Final',
              categoryId: 'final',
              prescriptions: [_prescription()],
            ),
            // 4: an archived timer still resolves where a plan uses it.
            PlanBlock(
              name: 'Viejo',
              categoryId: 'final',
              prescriptions: [_prescription(timerId: 'old')],
            ),
          ],
        ),
      ],
    ),
  ],
);

class _Groups implements AssignmentRepository {
  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    AthleteGroup(
      id: 'g1',
      clubId: clubId,
      name: 'Barra',
      memberIds: const ['ari'],
      auditoria: audit(),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Calendar implements CalendarRepository {
  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: date);
    return CalendarLocation(
      assignmentId: 'a1',
      planId: 'p1',
      startDate: _start,
      cycle: where.ciclo,
      week: where.semana,
    );
  }

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      _plan;

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to,
  ) async => const [];
}

class _Athletes implements AthleteRepository {
  @override
  Future<List<AthleteSummary>> athletes(String clubId) async => const [
    AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Stores every set the way the server would, with the kilos left empty: only the mark matters here.
class _Sessions implements SessionRepository {
  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async => LiveSession(
    session: Session(
      id: 's1',
      clubId: clubId,
      assignmentId: assignmentId,
      planId: 'p1',
      cycle: 3,
      week: week,
      day: day,
      date: date,
      presentAthleteIds: presentAthleteIds.toList(),
      auditoria: audit(),
    ),
    records: const [],
  );

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async => const [];

  bool refuse = false;

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    if (refuse) throw ErrorDeApi('refused', estado: 422);
    return SetRecord(
      id: 'r-${write.blockIndex}-${write.prescriptionIndex}',
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
      reps: 5,
      writtenBy: 'u1',
      auditoria: audit(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('timerForSet', () {
    final block = _plan.weekModels.first.days.first.blocks;

    test('the prescription\'s own timer wins over the block\'s', () {
      expect(
        timerForSet(block[1], block[1].prescriptions[1], _timers)?.id,
        'tabata',
      );
    });

    test('without its own, the set takes the block\'s default rest', () {
      expect(
        timerForSet(block[1], block[1].prescriptions[0], _timers)?.id,
        'rest60',
      );
    });

    test('a timed block\'s timer is not a rest', () {
      expect(timerForSet(block[2], block[2].prescriptions[0], _timers), isNull);
    });

    test('no timer, or one that is not in the catalog, starts nothing', () {
      expect(timerForSet(block[3], block[3].prescriptions[0], _timers), isNull);
      expect(
        timerForSet(block[0], block[0].prescriptions[0], const []),
        isNull,
      );
    });
  });

  group('on the session screen', () {
    late FakeTimerPlatform platform;
    late _Sessions sessions;

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      FakeTimerPlatform? with_,
    }) async {
      platform = with_ ?? FakeTimerPlatform();
      sessions = _Sessions();
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final me = meWith(
        [
          (club('c1', 'Gimnasio', TipoClub.club), {Rol.coach}),
        ],
        athleteIds: {'c1': 'ari'},
      );
      final catalog = FakeCatalogAdminRepository(
        exercisesList: [ex('sq', 'Sentadilla')],
        timersList: _timers,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meProvider.overrideWith((ref) async => me),
            catalogRepositoryProvider.overrideWithValue(catalog),
            catalogAdminRepositoryProvider.overrideWithValue(catalog),
            assignmentRepositoryProvider.overrideWithValue(_Groups()),
            calendarRepositoryProvider.overrideWithValue(_Calendar()),
            athleteRepositoryProvider.overrideWithValue(_Athletes()),
            sessionRepositoryProvider.overrideWithValue(sessions),
            todayProvider.overrideWithValue(_today),
            timerPlatformProvider.overrideWithValue(platform),
          ],
          child: MaterialApp(
            theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
            home: const SessionPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-open')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionPage)),
      );
      return container;
    }

    Future<void> mark(WidgetTester tester, String id) async {
      final check = find.byKey(Key('session-check-$id'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      // The timer ticks every 200 ms for as long as it runs, so the screen never settles.
      await tester.pump();
      await tester.pump();
    }

    String? running(ProviderContainer c) =>
        c.read(cronoControllerProvider)?.crono.temporizador.id;

    /// A test on the open session. A running timer is stopped at the end: its ticks outlive the widget tree.
    void scenario(
      String name,
      Future<void> Function(WidgetTester tester, ProviderContainer c) body, {
      FakeTimerPlatform? platform,
    }) => testWidgets(name, (tester) async {
      final c = await pump(tester, with_: platform);
      try {
        await body(tester, c);
      } finally {
        c.read(cronoControllerProvider.notifier).detener();
      }
    });

    scenario('marking a set starts the timer of its prescription', (
      tester,
      c,
    ) async {
      expect(running(c), isNull);

      await mark(tester, '0-0-0');

      expect(running(c), 'rest90');
      expect(c.read(cronoControllerProvider)!.segundos, 90);
      expect(platform.starts, 1);
    });

    scenario('a prescription without its own timer takes the block rest', (
      tester,
      c,
    ) async {
      await mark(tester, '1-0-0');
      expect(running(c), 'rest60');
    });

    scenario('a prescription own timer replaces the block one', (
      tester,
      c,
    ) async {
      await mark(tester, '1-1-0');
      expect(running(c), 'tabata');
    });

    scenario('an archived timer still starts where the plan uses it', (
      tester,
      c,
    ) async {
      await mark(tester, '4-0-0');
      expect(running(c), 'old');
    });

    scenario('sets without a timer, and those of a timed block, start none', (
      tester,
      c,
    ) async {
      await mark(tester, '3-0-0');
      expect(running(c), isNull);
      await mark(tester, '2-0-0');
      expect(running(c), isNull);
    });

    scenario('unmarking a set does not start the timer again', (
      tester,
      c,
    ) async {
      await mark(tester, '0-0-0');
      c.read(cronoControllerProvider.notifier).detener();
      await tester.pump();

      await mark(tester, '0-0-0');

      expect(running(c), isNull);
    });

    scenario('a write the server refuses starts no timer', (tester, c) async {
      sessions.refuse = true;

      await mark(tester, '0-0-0');

      expect(running(c), isNull);
    });

    scenario('the manual picker starts the timer the user chooses', (
      tester,
      c,
    ) async {
      await tester.tap(find.byKey(const Key('session-timer-pick')));
      await tester.pumpAndSettle();
      expect(find.text('Descanso viejo'), findsNothing, reason: 'archived');
      await tester.tap(find.text('AMRAP 12'));
      await tester.pump();
      await tester.pump();

      expect(running(c), 'amrap');
      expect(c.read(cronoControllerProvider)!.segundos, 720);
    });

    scenario(
      'with no sound, vibration or screen lock, marking a set still runs the timer',
      (tester, c) async {
        await mark(tester, '0-0-0');
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(running(c), 'rest90');
        expect(tester.takeException(), isNull);
        expect(platform.calls, contains('start'));
      },
      platform: FakeTimerPlatform(fail: true),
    );
  });
}
