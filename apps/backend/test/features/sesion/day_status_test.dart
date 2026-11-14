import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/day_status/day_status.dart';
import 'package:maktub_backend/features/sesion/day_status/day_status_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements DayStatusStore {
  final groups = <String>{};
  final assignments = <Assignment>[];
  final plans = <String, PublishedPlan>{};

  /// `clubId/assignmentId` → days with sets.
  final done = <String, List<DoneDay>>{};

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      groups.contains('$clubId/$groupId');

  @override
  Future<Assignment?> activeAssignment(String clubId, String groupId) async {
    for (final a in assignments) {
      if (a.clubId == clubId &&
          a.groupId == groupId &&
          a.status == AssignmentStatus.active) {
        return a;
      }
    }
    return null;
  }

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async =>
      plans['$clubId/$planId'];

  @override
  Future<List<DoneDay>> doneDays(
    String clubId,
    String assignmentId,
    List<int> cycles,
  ) async => [
    for (final d in done['$clubId/$assignmentId'] ?? const <DoneDay>[])
      if (cycles.contains(d.cycle)) d,
  ];
}

PublishedPlan _plan({int days = 3}) => PublishedPlan(
  weekModels: [
    WeekModel(
      id: 'w1',
      name: 'Base',
      days: [for (var i = 0; i < days; i++) const PlanDay()],
    ),
  ],
  weekAssignment: const ['w1', 'w1', 'w1', 'w1'],
  publishedAt: DateTime.utc(2026, 11, 8),
  publishedBy: 'coach',
);

Assignment _assignment(String clubId, {String planId = 'p1'}) => Assignment(
  id: 'a1',
  clubId: clubId,
  planId: planId,
  groupId: 'g1',
  startDate: DateTime.utc(2026, 11, 9),
  status: AssignmentStatus.active,
  auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 8)),
);

ClubContext _ctx(String clubId) => ClubContext(
  clubId: clubId,
  userId: 'u-1',
  roles: {Rol.atleta},
  clubType: TipoClub.club,
);

Future<Response> _get(_FakeStore s, String query) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x$query')));
  when(() => context.read<ClubContext>()).thenReturn(_ctx('club-a'));
  return manejarErrores()((c) => dayStatusEndpoint(c, 'g1', store: s))(context);
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  _FakeStore store() => _FakeStore()
    ..groups.add('club-a/g1')
    ..assignments.add(_assignment('club-a'))
    ..plans['club-a/p1'] = _plan();

  const week1 = '?desde=2026-11-09&hasta=2026-11-15';

  List<String> states(Map<String, dynamic> json) => [
    for (final d in json['dias'] as List)
      '${d['semana']}.${d['dia']}:${d['estado']}',
  ];

  group('status of each day', () {
    test('without sessions every day is pending', () async {
      final r = await _get(store(), week1);

      expect(r.statusCode, HttpStatus.ok);
      expect(states(await _json(r)), [
        '1.1:pendiente',
        '1.2:pendiente',
        '1.3:pendiente',
      ]);
    });

    test('a day with sets recorded is done, with its date', () async {
      final s = store()
        ..done['club-a/a1'] = [
          (cycle: 1, week: 1, day: 2, date: DateTime.utc(2026, 11, 11)),
        ];
      final json = await _json(await _get(s, week1));

      expect(states(json), ['1.1:pendiente', '1.2:hecho', '1.3:pendiente']);
      expect((json['dias'] as List)[1]['fecha'], '2026-11-11');
      expect((json['dias'] as List)[0].containsKey('fecha'), isFalse);
    });

    test('a range covers every week it touches, in order', () async {
      final json = await _json(
        await _get(store(), '?desde=2026-11-15&hasta=2026-11-17'),
      );

      expect(states(json).map((e) => e.split('.').first).toSet(), {'1', '2'});
      expect(states(json).first, '1.1:pendiente');
    });

    test('a range into the next cycle reads that cycle too', () async {
      final s = store()
        ..done['club-a/a1'] = [
          (cycle: 2, week: 1, day: 1, date: DateTime.utc(2026, 12, 7)),
          (cycle: 1, week: 4, day: 3, date: DateTime.utc(2026, 12, 3)),
        ];
      final json = await _json(
        await _get(s, '?desde=2026-12-01&hasta=2026-12-08'),
      );
      final days = json['dias'] as List;

      expect(days.where((d) => d['estado'] == 'hecho').length, 2);
      expect(days.map((d) => d['ciclo']).toSet(), {1, 2});
    });

    test('no active assignment gives an empty list', () async {
      final s = store()..assignments.clear();
      final json = await _json(await _get(s, week1));

      expect(json, {'asignacion': null, 'dias': <Object>[]});
    });

    test('an unknown group is 404, a plan not published is 422', () async {
      expect((await _get(store()..groups.clear(), week1)).statusCode, 404);
      expect((await _get(store()..plans.clear(), week1)).statusCode, 422);
    });

    test('bad dates are 400', () async {
      for (final q in [
        '',
        '?desde=2026-11-09',
        '?desde=2026-11-09&hasta=ayer',
        '?desde=2026-11-15&hasta=2026-11-09',
        '?desde=2020-01-01&hasta=2026-11-09',
      ]) {
        final r = await _get(store(), q);
        expect(r.statusCode, HttpStatus.badRequest, reason: q);
      }
    });
  });

  group('club isolation', () {
    final s = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/grupos/{grupoId}/dias',
      endpoint: (c) => dayStatusEndpoint(c, 'g1', store: s),
      path: '/clubes/{clubId}/grupos/g1/dias?desde=2026-11-09&hasta=2026-11-15',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) {
        s.groups.add('$clubId/g1');
        s.plans['$clubId/$marker'] = _plan();
        s.assignments.removeWhere((a) => a.clubId == clubId);
        s.assignments.add(_assignment(clubId, planId: marker));
      },
    );
  });
}
