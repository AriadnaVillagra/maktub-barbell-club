import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/offline/local_copy.dart';
import 'package:maktub_frontend/core/offline/shared_preferences_local_copy_store.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/asignacion/data/cached_calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/data/http_assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/data/http_calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoReporter implements LocalCopyReporter {
  @override
  void servedFresh() {}

  @override
  void servedFromCopy(DateTime savedAt) {}
}

/// Ari has 3 sets done of day 1, Andi 1; without signal it throws.
class _AthleteDays implements CalendarRepository {
  var offline = false;

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  }) async {
    if (offline) throw const ErrorDeApi('sin conexión');
    final done = athleteId == 'ari' ? 3 : 1;
    return [
      DayState(
        cycle: 1,
        week: 1,
        day: 1,
        status: DayProgressStatus.inProgress,
        doneSets: done,
        totalSets: 4,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The requests the repositories send and the answers they parse (E8.8: athlete's location, days by assignment and
/// assigning to an athlete).
void main() {
  late List<http.Request> sent;

  ClienteApi client(Object body) => ClienteApi(
    base: Uri.parse('http://api.test'),
    cliente: MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() => sent = []);

  test(
    "an athlete's location lists their group's plan and their own",
    () async {
      final repo = HttpCalendarRepository(
        client({
          'fecha': '2026-11-06',
          'ubicaciones': [
            {
              'asignacion': {
                'id': 'g',
                'planId': 'p1',
                'fechaInicio': '2026-10-01',
                'grupoId': 'g1',
              },
              'ciclo': 2,
              'semana': 1,
            },
            {
              'asignacion': {
                'id': 'own',
                'planId': 'lev',
                'fechaInicio': '2026-11-06',
                'atletaId': 'ari',
              },
              'ciclo': 1,
              'semana': 1,
            },
          ],
        }),
      );

      final located = await repo.locateAthlete(
        'c1',
        'ari',
        DateTime.utc(2026, 11, 6),
      );

      expect(
        sent.single.url.toString(),
        'http://api.test/clubes/c1/atletas/ari/ubicacion?fecha=2026-11-06',
      );
      expect(
        [for (final l in located) (l.assignmentId, l.groupId, l.athleteId)],
        [('g', 'g1', null), ('own', null, 'ari')],
      );
      expect((located.last.cycle, located.last.week), (1, 1));
      // The device's copy keeps whose each one is.
      expect(locationFromJson(locationToJson(located.last)).athleteId, 'ari');
    },
  );

  test('a location lists who is in the plan that day, and the copy keeps it (E6.7)', () async {
    final repo = HttpCalendarRepository(
      client({
        'fecha': '2026-11-18',
        'ubicaciones': [
          {
            'asignacion': {
              'id': 'a1',
              'planId': 'p1',
              'fechaInicio': '2026-11-02',
              'atletas': ['ari', 'luz'],
            },
            'ciclo': 1,
            'semana': 3,
          },
        ],
      }),
    );

    final located = (await repo.locateAthlete(
      'c1',
      'ari',
      DateTime.utc(2026, 11, 18),
    )).single;

    expect(located.athleteIds, ['ari', 'luz']);
    expect(locationFromJson(locationToJson(located)).athleteIds, [
      'ari',
      'luz',
    ]);
    // A copy saved before E6.7 has no list.
    expect(
      locationFromJson(locationToJson(located)..remove('atletas')).athleteIds,
      isNull,
    );
  });

  test('day states are read by assignment', () async {
    final repo = HttpCalendarRepository(
      client({
        'asignacion': {'id': 'own'},
        'dias': [
          {
            'ciclo': 1,
            'semana': 1,
            'dia': 1,
            'estado': 'hecho',
            'fecha': '2026-11-10',
          },
          {'ciclo': 1, 'semana': 1, 'dia': 2, 'estado': 'pendiente'},
        ],
      }),
    );

    final states = await repo.dayStates(
      'c1',
      'own',
      DateTime.utc(2026, 11, 6),
      DateTime.utc(2026, 12, 3),
    );

    expect(sent.single.url.path, '/clubes/c1/asignaciones/own/dias');
    expect(states.first.done, isTrue);
    // The date of the session it was done in, to look that session up on another date.
    expect(states.first.date, DateTime.utc(2026, 11, 10));
    expect(states.last.done, isFalse);
    expect(states.last.date, isNull);
  });

  test("one athlete's progress: atletaId goes out, counts come back", () async {
    final repo = HttpCalendarRepository(
      client({
        'asignacion': {'id': 'a1'},
        'dias': [
          {'ciclo': 1, 'semana': 1, 'dia': 1, 'estado': 'hecho', 'hechas': 4, 'total': 4},
          {'ciclo': 1, 'semana': 1, 'dia': 2, 'estado': 'en_curso', 'hechas': 12, 'total': 20},
          {'ciclo': 1, 'semana': 1, 'dia': 3, 'estado': 'pendiente', 'hechas': 0, 'total': 5},
        ],
      }),
    );

    final states = await repo.dayStates(
      'c1',
      'a1',
      DateTime.utc(2026, 11, 6),
      DateTime.utc(2026, 12, 3),
      athleteId: 'ari',
    );

    expect(sent.single.url.queryParameters['atletaId'], 'ari');
    expect(
      [for (final s in states) (s.status, s.doneSets, s.totalSets, s.done)],
      [
        (DayProgressStatus.done, 4, 4, true),
        (DayProgressStatus.inProgress, 12, 20, false),
        (DayProgressStatus.pending, 0, 5, false),
      ],
    );
    // The device's copy keeps the same.
    final copied = dayStateFromJson(dayStateToJson(states[1]));
    expect((copied.status, copied.doneSets, copied.totalSets), (DayProgressStatus.inProgress, 12, 20));
  });

  test("each athlete's days are kept apart on the device", () async {
    SharedPreferences.setMockInitialValues({});
    final remote = _AthleteDays();
    final reads = LocalCopyReads(SharedPreferencesLocalCopyStore(), _NoReporter());
    final repo = CachedCalendarRepository(remote, reads);
    final from = DateTime.utc(2026, 11, 6);
    final to = DateTime.utc(2026, 12, 3);

    await repo.dayStates('c1', 'a1', from, to, athleteId: 'ari');
    await repo.dayStates('c1', 'a1', from, to, athleteId: 'andi');
    remote.offline = true;

    expect((await repo.dayStates('c1', 'a1', from, to, athleteId: 'ari')).single.doneSets, 3);
    expect((await repo.dayStates('c1', 'a1', from, to, athleteId: 'andi')).single.doneSets, 1);
  });

  Map<String, Object?> answer(List<Map<String, String>> athletes) => {
    'id': 'a1',
    'clubId': 'c1',
    'planId': 'p1',
    'atletas': athletes,
    'fechaInicio': '2026-11-16',
    'estado': 'activa',
    'auditoria': Auditoria(
      creadoPor: 'u1',
      creadoEn: DateTime.utc(2026, 11, 15),
    ).toJson(),
  };

  test('assigning sends the list of athletes (E6.7)', () async {
    final repo = HttpAssignmentRepository(
      client(
        answer([
          {'atletaId': 'ari', 'desde': '2026-11-16'},
          {'atletaId': 'andi', 'desde': '2026-11-16'},
        ]),
      ),
    );

    final a = await repo.assign(
      'c1',
      planId: 'p1',
      athleteIds: ['ari', 'andi'],
      startDate: DateTime.utc(2026, 11, 16),
    );

    expect(sent.single.method, 'POST');
    expect(jsonDecode(sent.single.body), {
      'planId': 'p1',
      'atletas': ['ari', 'andi'],
      'fechaInicio': '2026-11-16',
    });
    expect(a.athleteIds, ['ari', 'andi']);
  });

  test('changing the athletes is a PUT with the list and the date', () async {
    final repo = HttpAssignmentRepository(
      client(
        answer([
          {'atletaId': 'ari', 'desde': '2026-11-16', 'hasta': '2026-11-17'},
          {'atletaId': 'andi', 'desde': '2026-11-18'},
        ]),
      ),
    );

    final a = await repo.setAthletes(
      'c1',
      'a1',
      athleteIds: ['andi'],
      date: DateTime.utc(2026, 11, 18),
    );

    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, '/clubes/c1/asignaciones/a1/atletas');
    expect(jsonDecode(sent.single.body), {
      'atletas': ['andi'],
      'fecha': '2026-11-18',
    });
    expect(a.currentAthleteIds, ['andi']);
  });
}
