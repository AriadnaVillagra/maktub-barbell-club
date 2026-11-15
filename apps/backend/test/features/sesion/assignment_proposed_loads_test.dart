import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/assignment_proposed_loads/assignment_proposed_loads.dart';
import 'package:maktub_backend/features/sesion/assignment_proposed_loads/assignment_proposed_loads_store.dart';
import 'package:maktub_backend/features/sesion/proposed_loads/proposed_loads.dart';
import 'package:maktub_backend/features/sesion/proposed_loads/proposed_loads_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

/// What both slices read, so the proposal by session and by date see the same world.
class _Data {
  final sessions = <String, Session>{};
  final assignments = <String, Assignment>{};
  final groups = <String, List<String>>{};
  final plans = <String, PublishedPlan>{};
  final athletes = <String, String>{};
  final catalog = <String, Map<String, Exercise>>{};
  final references = <Reference>[];
  final factors = <WorkFactor>[];
  final fixed = <FixedWeight>[];
  final equipments = <String, Equipo>{};
  var reads = 0;
}

class _Store implements AssignmentProposedLoadsStore {
  _Store(this.data);

  final _Data data;

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async =>
      data.assignments['$clubId/$assignmentId'];

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      data.groups['$clubId/$groupId'] ?? const [];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      data.athletes['$clubId/$userId'];

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async =>
      data.plans['$clubId/$planId'];

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async =>
      data.catalog[clubId] ?? const {};

  bool _matches(
    String clubId,
    Set<String> athleteIds,
    Set<String> exerciseIds,
    ({String clubId, String athleteId, String? exerciseId}) row,
  ) =>
      row.clubId == clubId &&
      athleteIds.contains(row.athleteId) &&
      exerciseIds.contains(row.exerciseId);

  @override
  Future<List<Reference>> references(
    String clubId,
    Set<String> athleteIds,
    Set<String> exerciseIds,
  ) async {
    data.reads++;
    return [
      for (final r in data.references)
        if (_matches(clubId, athleteIds, exerciseIds, (
          clubId: r.clubId,
          athleteId: r.athleteId,
          exerciseId: r.exerciseId,
        )))
          r,
    ];
  }

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    Set<String> athleteIds,
    Set<String> exerciseIds,
  ) async => [
    for (final f in data.factors)
      if (_matches(clubId, athleteIds, exerciseIds, (
        clubId: f.clubId,
        athleteId: f.athleteId,
        exerciseId: f.exerciseId,
      )))
        f,
  ];

  @override
  Future<List<FixedWeight>> fixedWeights(
    String clubId,
    Set<String> athleteIds,
    Set<String> exerciseIds,
  ) async => [
    for (final w in data.fixed)
      if (_matches(clubId, athleteIds, exerciseIds, (
        clubId: w.clubId,
        athleteId: w.athleteId,
        exerciseId: w.exerciseId,
      )))
        w,
  ];

  @override
  Future<Equipo?> equipment(String clubId) async => data.equipments[clubId];
}

/// The by-session slice over the same data, to compare against.
class _SessionStore implements ProposedLoadsStore {
  _SessionStore(this.data);

  final _Data data;
  late final _byDate = _Store(data);

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      data.sessions['$clubId/$sessionId'];

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) =>
      _byDate.assignment(clubId, assignmentId);

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) =>
      _byDate.groupMemberIds(clubId, groupId);

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) =>
      _byDate.athleteIdOfUser(clubId, userId);

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) =>
      _byDate.publishedPlan(clubId, planId);

  @override
  Future<Map<String, Exercise>> exercises(String clubId) =>
      _byDate.exercises(clubId);

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) => _byDate.references(clubId, {athleteId}, exerciseIds);

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) => _byDate.workFactors(clubId, {athleteId}, exerciseIds);

  @override
  Future<Map<String, FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => {
    for (final w in await _byDate.fixedWeights(clubId, {
      athleteId,
    }, exerciseIds))
      w.exerciseId: w,
  };

  @override
  Future<Equipo?> equipment(String clubId) => _byDate.equipment(clubId);
}

Exercise _exercise(
  String id, {
  LoadReference reference = const LoadReference.own(),
  double? barKg,
}) => Exercise(
  id: id,
  clubId: clubPlataforma,
  name: id,
  categoryIds: const ['primario'],
  metrics: const [Metric.loadPctRm],
  loadReference: reference,
  barKg: barKg,
  auditoria: _audit,
);

Reference _rm(
  String clubId,
  String exerciseId,
  double value, {
  String athleteId = 'ari',
  DateTime? date,
}) => Reference(
  id: 'rm-$athleteId-$exerciseId-$value',
  clubId: clubId,
  athleteId: athleteId,
  exerciseId: exerciseId,
  type: ReferenceType.rm,
  value: value,
  date: date ?? DateTime.utc(2026, 11, 1),
  origin: ReferenceOrigin.values.first,
  auditoria: _audit,
);

WorkFactor _factor(String clubId, String exerciseId, double value) =>
    WorkFactor(
      id: 'f-$exerciseId',
      clubId: clubId,
      athleteId: 'ari',
      exerciseId: exerciseId,
      value: value,
      date: DateTime.utc(2026, 11, 2),
      auditoria: _audit,
    );

PlanDay _day(String squatId, double pct) => PlanDay(
  blocks: [
    PlanBlock(
      name: 'Principal',
      prescriptions: [
        Prescription(
          exerciseId: squatId,
          sets: [
            PlanSet(reps: 5, pct: pct),
            PlanSet(reps: 5, pct: pct),
          ],
        ),
        const Prescription(
          exerciseId: 'accessory',
          sets: [PlanSet(reps: 12, kg: 10)],
        ),
        const Prescription(
          exerciseId: 'front',
          sets: [PlanSet(reps: 3, pct: 50)],
        ),
        const Prescription(
          exerciseId: 'barred',
          barKg: 15,
          sets: [PlanSet(reps: 3, pct: 16)],
        ),
      ],
    ),
  ],
);

/// Model A (weeks 1, 3, 4): day 1 at 80 %, day 2 at 70 %. Model B (week 2): one day at 90 %.
PublishedPlan _plan({String squatId = 'squat'}) => PublishedPlan(
  weekModels: [
    WeekModel(id: 'A', name: 'A', days: [_day(squatId, 80), _day(squatId, 70)]),
    WeekModel(id: 'B', name: 'B', days: [_day(squatId, 90)]),
  ],
  weekAssignment: const ['A', 'B', 'A', 'A'],
  publishedAt: DateTime.utc(2026, 11, 8),
  publishedBy: 'coach',
);

extension on _Data {
  void seed(String clubId, {String squatId = 'squat'}) {
    assignments['$clubId/a1'] = Assignment(
      id: 'a1',
      clubId: clubId,
      planId: 'p1',
      groupId: 'g1',
      startDate: DateTime.utc(2026, 11, 16),
      status: AssignmentStatus.active,
      auditoria: _audit,
    );
    groups['$clubId/g1'] = ['ari', 'andi'];
    plans['$clubId/p1'] = _plan(squatId: squatId);
    athletes['$clubId/user-ari'] = 'ari';
    catalog[clubId] = {
      squatId: _exercise(squatId),
      'accessory': _exercise(
        'accessory',
        reference: const LoadReference.none(),
      ),
      'front': _exercise(
        'front',
        reference: LoadReference.otherExercise(squatId),
      ),
      'barred': _exercise('barred'),
    };
    references
      ..add(_rm(clubId, squatId, 100))
      ..add(_rm(clubId, 'barred', 100))
      ..add(_rm(clubId, squatId, 120, athleteId: 'andi'));
  }

  void session(
    String id,
    DateTime date, {
    required int week,
    required int day,
  }) => sessions['club-a/$id'] = Session(
    id: id,
    clubId: 'club-a',
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 1,
    week: week,
    day: day,
    date: date,
    presentAthleteIds: const ['ari', 'andi'],
    auditoria: _audit,
  );
}

_Data _data() => _Data()..seed('club-a');

ClubContext _athlete({TipoClub type = TipoClub.club}) => ClubContext(
  clubId: 'club-a',
  userId: 'user-ari',
  roles: const {Rol.atleta},
  clubType: type,
);

ClubContext _coach() => const ClubContext(
  clubId: 'club-a',
  userId: 'coach',
  roles: {Rol.coach},
  clubType: TipoClub.club,
);

const _week = '?desde=2026-11-16&hasta=2026-11-24';

Future<Response> _get(
  _Data data, {
  String query = _week,
  ClubContext? club,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'GET',
      Uri.parse(
        'http://localhost/clubes/club-a/asignaciones/a1/kilos-propuestos$query',
      ),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => assignmentProposedLoadsEndpoint(c, 'a1', store: _Store(data)),
  )(context);
}

Future<Map<String, dynamic>> _body(
  _Data data, {
  String query = _week,
  ClubContext? club,
}) async {
  final response = await _get(data, query: query, club: club);
  final text = await response.body();
  expect(response.statusCode, HttpStatus.ok, reason: text);
  return jsonDecode(text) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _dates(Map<String, dynamic> body) =>
    (body['fechas'] as List).cast<Map<String, dynamic>>();

/// The sets of [athleteId] on [date], day [day].
List<dynamic> _sets(
  Map<String, dynamic> body,
  String date, {
  required int day,
  String athleteId = 'ari',
}) {
  final onDate = _dates(body).firstWhere((d) => d['fecha'] == date);
  final ofDay = (onDate['dias'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((d) => d['dia'] == day);
  final ofAthlete = (ofDay['atletas'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((a) => a['atletaId'] == athleteId);
  return ofAthlete['series'] as List;
}

Future<List<dynamic>> _bySession(
  _Data data,
  String sessionId, {
  String athleteId = 'ari',
  String query = '',
  ClubContext? club,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'GET',
      Uri.parse(
        'http://localhost/clubes/club-a/sesiones/$sessionId/atletas/$athleteId/kilos-propuestos$query',
      ),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  final response = await manejarErrores()(
    (c) => proposedLoadsEndpoint(
      c,
      sessionId,
      athleteId,
      store: _SessionStore(data),
    ),
  )(context);
  final text = await response.body();
  expect(response.statusCode, HttpStatus.ok, reason: text);
  return (jsonDecode(text) as Map)['series'] as List;
}

void main() {
  setUpAll(() => registerFallbackValue(_coach()));

  group('proposed kilos by assignment and date', () {
    test(
      'one entry per date, with its cycle, week and every day of that week',
      () async {
        final dates = _dates(await _body(_data()));

        expect(dates, hasLength(9));
        expect(dates.first['fecha'], '2026-11-16');
        expect(dates.first['ciclo'], 1);
        expect(dates.first['semana'], 1);
        expect(dates.first['dias'], hasLength(2));
        expect(dates.last['fecha'], '2026-11-24');
        expect(dates.last['semana'], 2);
        expect(dates.last['dias'], hasLength(1));
      },
    );

    test('the whole group by default, each with their own RM', () async {
      final body = await _body(_data());

      expect(_sets(body, '2026-11-16', day: 1).first['kilos'], 80);
      expect(
        _sets(body, '2026-11-16', day: 1, athleteId: 'andi').first['kilos'],
        pesoPorPorcentaje(rm: 120, pct: 80, equipo: Equipo.estandarDe('c')),
      );
      expect(_sets(body, '2026-11-24', day: 1).first['kilos'], 90);
    });

    test('kilos follow the references in force on each date', () async {
      final data = _data()
        ..references.add(
          _rm('club-a', 'squat', 110, date: DateTime.utc(2026, 11, 18)),
        );

      final body = await _body(data);

      expect(_sets(body, '2026-11-17', day: 1).first['kilos'], 80);
      expect(
        _sets(body, '2026-11-18', day: 1).first['kilos'],
        pesoPorPorcentaje(rm: 110, pct: 80, equipo: Equipo.estandarDe('c')),
      );
    });

    test('atletaId picks athletes of the group', () async {
      final body = await _body(_data(), query: '$_week&atletaId=andi');
      final day = (_dates(body).first['dias'] as List).first as Map;

      expect(
        [for (final a in day['atletas'] as List) (a as Map)['atletaId']],
        ['andi'],
      );
    });

    test('reads the references once for the whole range and group', () async {
      final data = _data();

      await _body(data);

      expect(data.reads, 1);
    });

    for (final (date, week, day, query) in [
      (DateTime.utc(2026, 11, 16), 1, 1, ''),
      (DateTime.utc(2026, 11, 17), 1, 2, '&ajuste=110'),
      (
        DateTime.utc(2026, 11, 24),
        2,
        1,
        '&ajuste=95&ajusteEjercicio=squat:105',
      ),
    ]) {
      test(
        'same kilos as the session endpoint (week $week, day $day$query)',
        () async {
          final data = _data()
            ..factors.add(_factor('club-a', 'squat', 90))
            ..fixed.add(
              FixedWeight(
                id: 'k1',
                clubId: 'club-a',
                athleteId: 'ari',
                exerciseId: 'accessory',
                kg: 22,
                auditoria: _audit,
              ),
            )
            ..session('s1', date, week: week, day: day);
          final iso = aIsoFecha(date);

          for (final athleteId in ['ari', 'andi']) {
            final bySession = await _bySession(
              data,
              's1',
              athleteId: athleteId,
              query: query.isEmpty ? '' : '?${query.substring(1)}',
            );
            final byDate = _sets(
              await _body(data, query: '?desde=$iso&hasta=$iso$query'),
              iso,
              day: day,
              athleteId: athleteId,
            );

            expect(byDate, bySession);
            expect(byDate, isNotEmpty);
          }
        },
      );
    }

    test('writes nothing and needs no session', () async {
      final data = _data();

      await _body(data);

      expect(data.sessions, isEmpty);
    });

    test('a plan with no published version is unprocessable', () async {
      final data = _data()..plans.remove('club-a/p1');

      expect((await _get(data)).statusCode, HttpStatus.unprocessableEntity);
    });
  });

  group('what an athlete is told', () {
    test('their kilos without the factor, the same a coach sees', () async {
      final data = _data()..factors.add(_factor('club-a', 'squat', 90));

      final coach = await _body(data);
      final response = await _get(data, club: _athlete());
      final text = await response.body();

      expect(response.statusCode, HttpStatus.ok);
      expect(_sets(coach, '2026-11-16', day: 1).first['factor'], 90);
      expect(text, isNot(contains('factor')));
      expect(
        _sets(jsonDecode(text) as Map<String, dynamic>, '2026-11-16', day: 1),
        [
          for (final s in _sets(coach, '2026-11-16', day: 1))
            (Map.of(s as Map)..remove('factor')),
        ],
      );
    });
  });

  group('permissions', () {
    test('an athlete of the group gets the group', () async {
      final body = await _body(_data(), club: _athlete());
      final day = (_dates(body).first['dias'] as List).first as Map;

      expect(day['atletas'], hasLength(2));
    });

    test("an athlete's own assignment proposes only for them; another athlete gets not found", () async {
      Assignment own(String athleteId) => Assignment(
        id: 'a1',
        clubId: 'club-a',
        planId: 'p1',
        athleteId: athleteId,
        startDate: DateTime.utc(2026, 11, 16),
        auditoria: _audit,
      );
      final data = _data()..assignments['club-a/a1'] = own('ari');
      final day = (_dates(await _body(data, club: _athlete())).first['dias'] as List).first as Map;
      expect([for (final a in day['atletas'] as List) (a as Map)['atletaId']], ['ari']);

      data.assignments['club-a/a1'] = own('andi');
      expect((await _get(data, club: _athlete())).statusCode, HttpStatus.notFound);
    });

    test('an athlete outside the group gets not found', () async {
      final data = _data()..groups['club-a/g1'] = ['andi'];

      expect(
        (await _get(data, club: _athlete())).statusCode,
        HttpStatus.notFound,
      );
    });

    test('in a personal club an athlete gets only themselves', () async {
      final club = _athlete(type: TipoClub.personal);
      final body = await _body(_data(), club: club);
      final day = (_dates(body).first['dias'] as List).first as Map;

      expect(day['atletas'], hasLength(1));
      expect(
        (await _get(
          _data(),
          query: '$_week&atletaId=andi',
          club: club,
        )).statusCode,
        HttpStatus.forbidden,
      );
    });

    test('an athlete not in the group is unprocessable', () async {
      final response = await _get(_data(), query: '$_week&atletaId=luz');

      expect(response.statusCode, HttpStatus.unprocessableEntity);
    });

    test('an assignment of another club is not found', () async {
      final data = _Data()..seed('club-b');

      expect((await _get(data)).statusCode, HttpStatus.notFound);
    });
  });

  group('malformed requests', () {
    for (final query in [
      '',
      '?desde=2026-11-16',
      '?desde=2026-11-16&hasta=ayer',
      '?desde=2026-11-16&hasta=2026-11-15',
      '?desde=2026-11-01&hasta=2026-12-02',
      '$_week&ajuste=200',
      '$_week&ajusteEjercicio=squat',
    ]) {
      test('"$query" is a bad request', () async {
        expect(
          (await _get(_data(), query: query)).statusCode,
          HttpStatus.badRequest,
        );
      });
    }
  });

  final isolated = _Data();
  testClubIsolation(
    'GET /clubes/{clubId}/asignaciones/{asignacionId}/kilos-propuestos',
    endpoint: (context) =>
        assignmentProposedLoadsEndpoint(context, 'a1', store: _Store(isolated)),
    path: '/clubes/{clubId}/asignaciones/a1/kilos-propuestos?desde=2026-11-16&hasta=2026-11-16',
    action: Accion.registrar,
    seed: (clubId, marker) {
      isolated.seed(clubId, squatId: marker);
      isolated.athletes['$clubId/u1'] = 'ari';
    },
  );
}
