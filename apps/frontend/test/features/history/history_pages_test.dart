import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/modos.dart';
import 'package:maktub_frontend/app/router.dart' show Rutas;
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/athlete_sheet_page.dart';
import 'package:maktub_frontend/features/atletas/presentation/athletes_page.dart';
import 'package:maktub_frontend/features/atletas/presentation/profile_page.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/history/domain/history_labels.dart';
import 'package:maktub_frontend/features/history/domain/history_repository.dart';
import 'package:maktub_frontend/features/history/presentation/history_page.dart';
import 'package:maktub_frontend/features/history/presentation/providers.dart';
import 'package:maktub_frontend/features/history/presentation/session_history_page.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../atletas/fakes.dart' show FakeAthleteRepository;
import '../catalogo/catalog_fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 4, 3));

HistoryEntry _entry(
  String id,
  DateTime date, {
  String? plan = 'Abril 2026',
  PlanType? type = PlanType.history,
  int done = 3,
  int total = 5,
  int estimated = 0,
}) => HistoryEntry(
  sessionId: id,
  date: date,
  assignmentId: 'as1',
  planId: 'p1',
  planName: plan,
  planType: plan == null ? null : type,
  cycle: 1,
  week: 2,
  day: 3,
  dayName: 'Pierna',
  done: done,
  total: total,
  estimated: estimated,
);

SetRecord _record(
  int set, {
  double? kg,
  int? reps,
  bool done = true,
  bool estimated = false,
  String? note,
}) => SetRecord(
  id: 'r$set',
  clubId: 'c1',
  sessionId: 's1',
  athleteId: 'a1',
  exerciseId: 'sq',
  exerciseName: 'Sentadilla',
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: set,
  kg: kg,
  reps: reps,
  done: done,
  estimated: estimated,
  note: note,
  writtenBy: 'u1',
  auditoria: _audit,
);

class _FakeHistory implements HistoryRepository {
  _FakeHistory({this.pages = const {}, this.sessions = const {}, this.failure});

  /// Pages by `antesDe` (null for the first).
  final Map<DateTime?, HistoryPage> pages;
  final Map<String, SessionHistory> sessions;
  Object? failure;
  Completer<void>? gate;
  final calls = <String>[];

  @override
  Future<HistoryPage> page(
    String clubId,
    String athleteId, {
    DateTime? before,
  }) async {
    calls.add(
      'page:$clubId:$athleteId:${before == null ? '-' : aIsoFecha(before)}',
    );
    await gate?.future;
    if (failure != null) throw failure!;
    return pages[before] ?? const HistoryPage();
  }

  @override
  Future<SessionHistory> session(
    String clubId,
    String athleteId,
    String sessionId,
  ) async {
    calls.add('session:$clubId:$athleteId:$sessionId');
    if (failure != null) throw failure!;
    return sessions[sessionId] ??
        (throw const ErrorDeApi('Historial no encontrado.', estado: 404));
  }
}

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

List<Override> _overrides(
  _FakeHistory repo, {
  Set<Rol> roles = const {Rol.atleta},
  FakeAthleteRepository? athletes,
}) => [
  sessionControllerProvider.overrideWith(_SignedIn.new),
  meRepositoryProvider.overrideWithValue(
    FakeMeRepository(
      meWith(
        [(club('c1', 'Gimnasio', TipoClub.club), roles)],
        athleteIds: const {'c1': 'a1'},
      ),
    ),
  ),
  historyRepositoryProvider.overrideWithValue(repo),
  catalogRepositoryProvider.overrideWithValue(FakeCatalog(const [])),
  athleteRepositoryProvider.overrideWithValue(
    athletes ??
        FakeAthleteRepository(
          sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
        ),
  ),
  todayProvider.overrideWithValue(DateTime.utc(2026, 11, 21)),
];

/// Mounts [routes] behind a router that starts at [initial].
Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  _FakeHistory repo,
  List<RouteBase> routes,
  String initial, {
  Set<Rol> roles = const {Rol.atleta},
  FakeAthleteRepository? athletes,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: routes);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo, roles: roles, athletes: athletes),
      child: MaterialApp.router(
        theme: TemaMaktub.claro(),
        routerConfig: router,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return router;
}

final _historyRoutes = [
  GoRoute(
    path: '/h',
    builder: (_, _) => const OwnHistoryPage(basePath: '/h'),
    routes: [
      GoRoute(
        path: ':sessionId',
        builder: (_, state) => OwnSessionHistoryPage(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
    ],
  ),
];

void main() {
  group('history list', () {
    testWidgets(
      'lists the sessions newest first, by month, with plan, day and sets',
      (tester) async {
        final repo = _FakeHistory(
          pages: {
            null: HistoryPage(
              entries: [
                _entry(
                  's-oct',
                  DateTime.utc(2026, 10, 1),
                  plan: 'Octubre',
                  type: PlanType.regular,
                  done: 5,
                ),
                _entry('s-gone', DateTime.utc(2026, 9, 1), plan: null),
                _entry('s-apr', DateTime.utc(2026, 4, 3), estimated: 2),
              ],
            ),
          },
        );
        await _pumpRouter(tester, repo, _historyRoutes, '/h');
        expect(repo.calls, ['page:c1:a1:-']);
        expect(find.text('Historial'), findsOneWidget);
        for (final month in ['Octubre 2026', 'Septiembre 2026']) {
          expect(find.text(month), findsOneWidget);
        }
        // April's header and the plan named after it.
        expect(find.text('Abril 2026'), findsNWidgets(2));
        expect(find.text('Octubre'), findsOneWidget);
        expect(find.text('Plan eliminado'), findsOneWidget);
        expect(
          find.text('vie 3 abr 2026 · Ciclo 1 · Semana 2 · Día 3 (Pierna)'),
          findsOneWidget,
        );
        expect(find.text('5/5 series'), findsOneWidget);
        expect(find.text('3/5 series'), findsNWidgets(2));
        expect(find.text('2 estimadas'), findsOneWidget);
        expect(find.text('Histórico'), findsNWidgets(1));
        // Older ones are not offered when there are none.
        expect(find.byKey(const Key('history-more')), findsNothing);
        // Newest first.
        expect(
          tester.getTopLeft(find.byKey(const Key('history-s-oct'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('history-s-apr'))).dy,
          ),
        );
      },
    );

    testWidgets(
      '"Cargar más" brings the older page with the cursor and then disappears',
      (tester) async {
        final repo = _FakeHistory(
          pages: {
            null: HistoryPage(
              entries: [_entry('s2', DateTime.utc(2026, 4, 3))],
              next: DateTime.utc(2026, 4, 3),
            ),
            DateTime.utc(2026, 4, 3): HistoryPage(
              entries: [_entry('s1', DateTime.utc(2025, 5, 10))],
            ),
          },
        );
        await _pumpRouter(tester, repo, _historyRoutes, '/h');
        expect(find.byKey(const Key('history-s1')), findsNothing);
        await tester.tap(find.byKey(const Key('history-more')));
        await tester.pumpAndSettle();
        expect(repo.calls.last, 'page:c1:a1:2026-04-03');
        expect(find.byKey(const Key('history-s1')), findsOneWidget);
        expect(find.text('Mayo 2025'), findsOneWidget);
        expect(find.byKey(const Key('history-more')), findsNothing);
      },
    );

    testWidgets('a failed "Cargar más" keeps the list and offers to retry', (
      tester,
    ) async {
      final repo = _FakeHistory(
        pages: {
          null: HistoryPage(
            entries: [_entry('s2', DateTime.utc(2026, 4, 3))],
            next: DateTime.utc(2026, 4, 3),
          ),
        },
      );
      await _pumpRouter(tester, repo, _historyRoutes, '/h');
      repo.failure = const ErrorDeApi('Sin conexión.', estado: 503);
      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-s2')), findsOneWidget);
      expect(find.text('Sin conexión.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('shows an empty state', (tester) async {
      await _pumpRouter(tester, _FakeHistory(), _historyRoutes, '/h');
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
    });

    testWidgets('shows the loading state and the backend error', (
      tester,
    ) async {
      final repo = _FakeHistory(
        failure: const ErrorDeApi('Historial no encontrado.', estado: 404),
      )..gate = Completer<void>();
      await _pumpRouter(tester, repo, _historyRoutes, '/h', settle: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Historial no encontrado.'), findsOneWidget);
    });

    testWidgets('tapping a session opens its detail', (tester) async {
      final repo = _FakeHistory(
        pages: {
          null: HistoryPage(entries: [_entry('s1', DateTime.utc(2026, 4, 3))]),
        },
        sessions: {
          's1': SessionHistory(entry: _entry('s1', DateTime.utc(2026, 4, 3))),
        },
      );
      final router = await _pumpRouter(tester, repo, _historyRoutes, '/h');
      await tester.tap(find.byKey(const Key('history-s1')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/h/s1');
      expect(repo.calls.last, 'session:c1:a1:s1');
      expect(find.byKey(const Key('session-history-plan')), findsOneWidget);
    });

    testWidgets("the coach's history carries the athlete's name", (
      tester,
    ) async {
      final repo = _FakeHistory();
      await _pumpRouter(
        tester,
        repo,
        [
          GoRoute(
            path: '/c',
            builder: (_, _) =>
                const CoachHistoryPage(athleteId: 'a2', basePath: '/c'),
          ),
        ],
        '/c',
        roles: {Rol.coach},
        athletes: FakeAthleteRepository(
          athletesList: const [
            AthleteSummary(id: 'a2', userId: 'u2', name: 'Andi'),
          ],
        ),
      );
      expect(find.text('Historial de Andi'), findsOneWidget);
      expect(repo.calls, ['page:c1:a2:-']);
    });
  });

  group('session detail', () {
    SessionHistory detail() => SessionHistory(
      entry: _entry(
        's1',
        DateTime.utc(2026, 4, 3),
        estimated: 1,
        done: 2,
        total: 5,
      ),
      note: 'Buen día',
      blocks: [
        HistoryBlock(
          index: 0,
          name: 'Principal',
          seconds: 905,
          interrupted: true,
          exercises: [
            HistoryExercise(
              index: 0,
              exerciseId: 'sq',
              exerciseName: 'Sentadilla',
              sets: [
                HistorySet(
                  index: 0,
                  target: const PlanSet(reps: 5, pct: 70),
                  record: _record(0, kg: 72.5, reps: 5, note: 'Rodilla bien'),
                ),
                HistorySet(
                  index: 1,
                  target: const PlanSet(reps: 5, pct: 75),
                  record: _record(1, kg: 77.5, reps: 5, estimated: true),
                ),
                HistorySet(
                  index: 2,
                  target: const PlanSet(reps: 5, pct: 80),
                  record: _record(2, done: false),
                ),
              ],
            ),
            const HistoryExercise(
              index: 1,
              exerciseId: 'bench',
              exerciseName: 'Press de banca',
              sets: [
                HistorySet(
                  index: 0,
                  target: PlanSet(
                    reps: 8,
                    pct: 60,
                    byAthlete: {'a1': AthleteSetLoad(pct: 60, kg: 50)},
                  ),
                ),
              ],
            ),
          ],
        ),
        const HistoryBlock(index: 2),
      ],
    );

    Future<void> pumpDetail(WidgetTester tester, _FakeHistory repo) async {
      await _pumpRouter(tester, repo, [
        GoRoute(
          path: '/d',
          builder: (_, _) =>
              const SessionHistoryPage(athleteId: 'a1', sessionId: 's1'),
        ),
      ], '/d');
    }

    testWidgets('shows the plan, day, note, blocks and each set as recorded', (
      tester,
    ) async {
      final repo = _FakeHistory(sessions: {'s1': detail()});
      await pumpDetail(tester, repo);
      expect(repo.calls, ['session:c1:a1:s1']);
      expect(find.text('vie 3 abr 2026'), findsOneWidget);
      expect(find.text('Abril 2026'), findsOneWidget);
      expect(find.text('Ciclo 1 · Semana 2 · Día 3 (Pierna)'), findsOneWidget);
      expect(find.text('2/5 series'), findsOneWidget);
      expect(find.text('1 estimada'), findsOneWidget);
      expect(find.text('Buen día'), findsOneWidget);

      expect(find.text('Principal'), findsOneWidget);
      expect(find.text('15:05 (interrumpido)'), findsOneWidget);
      expect(find.text('Bloque 3'), findsOneWidget);

      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Rodilla bien'), findsOneWidget);
      final first = find.byKey(const Key('history-set-0-0-0'));
      expect(
        find.descendant(of: first, matching: find.text('72.5 kg × 5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('Objetivo: 5 al 70 %')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );

      final estimated = find.byKey(const Key('history-set-0-0-1'));
      expect(
        find.descendant(of: estimated, matching: find.text('Estimada')),
        findsOneWidget,
      );

      final notDone = find.byKey(const Key('history-set-0-0-2'));
      expect(
        find.descendant(of: notDone, matching: find.text('Sin hacer')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: notDone,
          matching: find.byIcon(Icons.cancel_outlined),
        ),
        findsOneWidget,
      );

      final unrecorded = find.byKey(const Key('history-set-0-1-0'));
      expect(
        find.descendant(of: unrecorded, matching: find.text('Sin registrar')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: unrecorded,
          matching: find.text('Objetivo: 8 al 60 % (50 kg)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is read-only: no buttons to change anything', (tester) async {
      await pumpDetail(tester, _FakeHistory(sessions: {'s1': detail()}));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a session with nothing recorded says so', (tester) async {
      final repo = _FakeHistory(
        sessions: {
          's1': SessionHistory(entry: _entry('s1', DateTime.utc(2026, 4, 3))),
        },
      );
      await pumpDetail(tester, repo);
      expect(find.byKey(const Key('session-history-empty')), findsOneWidget);
    });

    testWidgets('shows the backend error with a retry', (tester) async {
      await pumpDetail(tester, _FakeHistory());
      expect(find.text('Historial no encontrado.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('ways in', () {
    testWidgets('the training landing opens the own history', (tester) async {
      final repo = _FakeHistory();
      final router = await _pumpRouter(tester, repo, [
        GoRoute(
          path: Rutas.entrenamiento,
          builder: (_, _) => const PaginaEntrenamiento(),
          routes: [
            GoRoute(
              path: 'historial',
              builder: (_, _) => const OwnHistoryPage(basePath: Rutas.historial),
            ),
          ],
        ),
      ], Rutas.entrenamiento);
      await tester.tap(find.byKey(const Key('portada-${Rutas.historial}')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Rutas.historial);
      expect(repo.calls, ['page:c1:a1:-']);
    });

    testWidgets('the old Perfil path redirects to the training history', (tester) async {
      final repo = _FakeHistory();
      final router = await _pumpRouter(tester, repo, [
        GoRoute(
          path: Rutas.entrenamiento,
          builder: (_, _) => const SizedBox(),
          routes: [
            GoRoute(
              path: 'historial',
              builder: (_, _) => const OwnHistoryPage(basePath: Rutas.historial),
            ),
          ],
        ),
        GoRoute(
          path: Rutas.perfil,
          builder: (_, _) => const SizedBox(),
          routes: [
            GoRoute(
              path: 'historial',
              redirect: (_, state) => state.uri.toString().replaceFirst(Rutas.historialAntiguo, Rutas.historial),
            ),
          ],
        ),
      ], Rutas.historialAntiguo);
      expect(router.state.uri.path, Rutas.historial);
      expect(find.byType(OwnHistoryPage), findsOneWidget);
    });

    testWidgets("the athletes list has a history action per athlete", (tester) async {
      final repo = _FakeHistory();
      final router = await _pumpRouter(
        tester,
        repo,
        [
          GoRoute(
            path: '/a',
            builder: (_, _) => const AthletesPage(basePath: '/a'),
            routes: [GoRoute(path: ':id/historial', builder: (_, _) => const SizedBox())],
          ),
        ],
        '/a',
        roles: {Rol.coach},
        athletes: FakeAthleteRepository(athletesList: const [AthleteSummary(id: 'a2', userId: 'u2', name: 'Andi')]),
      );
      final button = find.byWidgetPredicate((w) => w.key.toString().contains('athlete-history-'));
      expect(button, findsWidgets);
      await tester.tap(button.first);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, endsWith('/historial'));
    });

    testWidgets("the coach's athlete sheet opens that athlete's history", (
      tester,
    ) async {
      final repo = _FakeHistory();
      final router = await _pumpRouter(
        tester,
        repo,
        [
          GoRoute(
            path: '/a/:id',
            builder: (_, state) => AthleteSheetPage(
              athleteId: state.pathParameters['id']!,
              historyPath: '/a/${state.pathParameters['id']}/historial',
            ),
            routes: [
              GoRoute(
                path: 'historial',
                builder: (_, state) => CoachHistoryPage(
                  athleteId: state.pathParameters['id']!,
                  basePath: '/x',
                ),
              ),
            ],
          ),
        ],
        '/a/a2',
        roles: {Rol.coach},
        athletes: FakeAthleteRepository(
          sheets: {'a2': const AthleteSheet(athleteId: 'a2')},
        ),
      );
      await tester.tap(find.byKey(const Key('sheet-history')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/a/a2/historial');
      expect(repo.calls, ['page:c1:a2:-']);
    });

    testWidgets('without a history path neither way in shows', (tester) async {
      await _pumpRouter(tester, _FakeHistory(), [
        GoRoute(path: '/p', builder: (_, _) => const ProfilePage()),
        GoRoute(
          path: '/s',
          builder: (_, _) => const AthleteSheetPage(athleteId: 'a1'),
        ),
      ], '/p');
      expect(find.byKey(const Key('profile-history')), findsNothing);
    });
  });

  group('labels', () {
    test('format dates, durations, targets and records', () {
      expect(historyDateLabel(DateTime.utc(2026, 11, 21)), 'sáb 21 nov 2026');
      expect(historyMonthLabel(DateTime.utc(2025, 5, 1)), 'Mayo 2025');
      expect(durationLabel(65), '1:05');
      expect(durationLabel(3725), '1:02:05');
      expect(targetLabel(const PlanSet(reps: 8, kg: 20)), '8 con 20 kg');
      expect(targetLabel(const PlanSet(maxReps: true)), 'Máx.');
      expect(targetLabel(const PlanSet(seconds: 45)), '45 s');
      expect(targetLabel(const PlanSet()), '');
      expect(
        targetLabel(
          const PlanSet(
            reps: 5,
            pct: 70,
            byAthlete: {'a2': AthleteSetLoad(kg: 60)},
          ),
          athleteId: 'a1',
        ),
        '5 al 70 %',
      );
      expect(recordLabel(_record(0, reps: 12)), '× 12');
      expect(recordLabel(_record(0)), '');
    });
  });
}
