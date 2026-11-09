import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/proposed_loads/proposed_loads.dart';
import 'package:maktub_backend/features/sesion/proposed_loads/proposed_loads_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

/// The data both stores read, so a proposal and a recorded set see the same world.
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
}

class _Store implements ProposedLoadsStore {
  _Store(this.data);

  final _Data data;

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      data.sessions['$clubId/$sessionId'];

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

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => [
    for (final r in data.references)
      if (r.clubId == clubId &&
          r.athleteId == athleteId &&
          exerciseIds.contains(r.exerciseId))
        r,
  ];

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => [
    for (final f in data.factors)
      if (f.clubId == clubId &&
          f.athleteId == athleteId &&
          exerciseIds.contains(f.exerciseId))
        f,
  ];

  @override
  Future<Map<String, FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
    Set<String> exerciseIds,
  ) async => {
    for (final w in data.fixed)
      if (w.clubId == clubId &&
          w.athleteId == athleteId &&
          exerciseIds.contains(w.exerciseId))
        w.exerciseId: w,
  };

  @override
  Future<Equipo?> equipment(String clubId) async => data.equipments[clubId];
}

class _RecordStore implements RecordSetStore {
  _RecordStore(this.data);

  final _Data data;
  late final _proposals = _Store(data);

  @override
  Future<Session?> session(String clubId, String sessionId) =>
      _proposals.session(clubId, sessionId);

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) =>
      _proposals.publishedPlan(clubId, planId);

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) =>
      _proposals.athleteIdOfUser(clubId, userId);

  @override
  Future<Map<String, Exercise>> exercises(String clubId) =>
      _proposals.exercises(clubId);

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    String exerciseId,
  ) => _proposals.references(clubId, athleteId, {exerciseId});

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    String exerciseId,
  ) => _proposals.workFactors(clubId, athleteId, {exerciseId});

  @override
  Future<FixedWeight?> fixedWeight(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => (await _proposals.fixedWeights(clubId, athleteId, {
    exerciseId,
  }))[exerciseId];

  @override
  Future<Equipo?> equipment(String clubId) => _proposals.equipment(clubId);

  @override
  Future<SetRecord> upsert(SetRecord record, {bool keepNote = false}) async =>
      record;
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

Reference _rm(String clubId, String exerciseId, double value) => Reference(
  id: 'rm-$exerciseId',
  clubId: clubId,
  athleteId: 'ari',
  exerciseId: exerciseId,
  type: ReferenceType.rm,
  value: value,
  date: DateTime.utc(2026, 11, 1),
  origin: ReferenceOrigin.values.first,
  auditoria: _audit,
);

WorkFactor _factor(String clubId, String exerciseId, double value) => WorkFactor(
  id: 'f-$exerciseId',
  clubId: clubId,
  athleteId: 'ari',
  exerciseId: exerciseId,
  value: value,
  date: DateTime.utc(2026, 11, 2),
  auditoria: _audit,
);

/// Day 1: 0 `squat` (2 × 80 %), 1 `accessory` (no %, 10 kg in the plan), 2 `front` (50 % of `squat`'s RM),
/// 3 `barred` (16 % on the prescription's 15 kg bar).
PublishedPlan _plan({String squatId = 'squat'}) => PublishedPlan(
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'A',
      days: [
        PlanDay(
          blocks: [
            PlanBlock(
              name: 'Principal',
              prescriptions: [
                Prescription(
                  exerciseId: squatId,
                  sets: const [
                    PlanSet(reps: 5, pct: 80),
                    PlanSet(reps: 5, pct: 80),
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
        ),
      ],
    ),
  ],
  weekAssignment: const ['A', 'A', 'A', 'A'],
  publishedAt: DateTime.utc(2026, 11, 8),
  publishedBy: 'coach',
);

extension on _Data {
  void seed(String clubId, {String squatId = 'squat'}) {
    sessions['$clubId/s1'] = Session(
      id: 's1',
      clubId: clubId,
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 1,
      week: 1,
      day: 1,
      date: DateTime.utc(2026, 11, 16),
      presentAthleteIds: const ['ari', 'andi'],
      auditoria: _audit,
    );
    assignments['$clubId/a1'] = Assignment(
      id: 'a1',
      clubId: clubId,
      planId: 'p1',
      groupId: 'g1',
      startDate: DateTime.utc(2026, 11, 16),
      status: AssignmentStatus.active,
      auditoria: _audit,
    );
    groups['$clubId/g1'] = ['ari', 'andi', 'luz'];
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
    references.add(_rm(clubId, squatId, 100));
  }
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

Future<Response> _get(
  _Data data, {
  String athleteId = 'ari',
  String query = '',
  ClubContext? club,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'GET',
      Uri.parse(
        'http://localhost/clubes/club-a/sesiones/s1/atletas/$athleteId/kilos-propuestos$query',
      ),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => proposedLoadsEndpoint(c, 's1', athleteId, store: _Store(data)),
  )(context);
}

Future<List<Map<String, dynamic>>> _sets(
  _Data data, {
  String athleteId = 'ari',
  String query = '',
  ClubContext? club,
}) async {
  final response = await _get(
    data,
    athleteId: athleteId,
    query: query,
    club: club,
  );
  final text = await response.body();
  expect(response.statusCode, HttpStatus.ok, reason: text);
  return ((jsonDecode(text) as Map)['series'] as List)
      .cast<Map<String, dynamic>>();
}

Future<SetRecord> _recorded(_Data data, Map<String, dynamic> position) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'PUT',
      Uri.parse('http://localhost/clubes/club-a/sesiones/s1/registros'),
      body: jsonEncode({'atletaId': 'ari', ...position}),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(_coach());
  final response = await manejarErrores()(
    (c) => recordSetEndpoint(
      c,
      's1',
      store: _RecordStore(data),
      newId: () => 'r1',
      now: () => DateTime.utc(2026, 11, 16, 10),
    ),
  )(context);
  return SetRecord.fromJson(
    jsonDecode(await response.body()) as Map<String, dynamic>,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(_coach()));

  group('proposed kilos', () {
    test('returns one entry per set of the day, with its position', () async {
      final sets = await _sets(_data());

      expect(sets, hasLength(5));
      expect(sets[1]['bloque'], 0);
      expect(sets[1]['prescripcion'], 0);
      expect(sets[1]['serie'], 1);
      expect(sets[1]['ejercicioId'], 'squat');
    });

    test('RM × factor × percent of the plan, nearest loadable (E4)', () async {
      final data = _data()..factors.add(_factor('club-a', 'squat', 90));
      final expected = pesoPorPorcentaje(
        rm: 100,
        pct: 80,
        equipo: Equipo.estandarDe('club-a'),
        workFactor: 90,
      );

      final sets = await _sets(data);

      expect(sets.first['kilos'], expected);
      expect(sets.first['factor'], 90);
      expect(sets.first['pctAplicado'], 80);
    });

    test('with a neutral factor it is RM × percent and carries no factor', () async {
      final sets = await _sets(_data());

      expect(sets.first['kilos'], 80);
      expect(sets.first, isNot(contains('factor')));
    });

    test('an exercise referencing another uses the RM at the end of the chain', () async {
      final sets = await _sets(_data());

      expect(sets[3]['ejercicioId'], 'front');
      expect(sets[3]['kilos'], 50);
    });

    test('the athlete\'s fixed kilos go first and then the plan\'s', () async {
      final data = _data();

      expect((await _sets(data))[2]['kilos'], 10);

      data.fixed.add(
        FixedWeight(
          id: 'k1',
          clubId: 'club-a',
          athleteId: 'ari',
          exerciseId: 'accessory',
          kg: 22,
          auditoria: _audit,
        ),
      );
      expect((await _sets(data))[2]['kilos'], 22);
    });

    test('uses the prescription\'s bar', () async {
      final data = _data()..references.add(_rm('club-a', 'barred', 100));
      final expected = pesoPorPorcentaje(
        rm: 100,
        pct: 16,
        equipo: Equipo.estandarDe('club-a'),
        barKg: 15,
      );

      expect((await _sets(data))[4]['kilos'], expected);
    });

    test('without an RM there are no kilos, never zero', () async {
      final sets = await _sets(_data(), athleteId: 'andi');

      expect(sets.first, isNot(contains('kilos')));
    });

    test('the session and exercise adjustments apply; the exercise one wins', () async {
      final data = _data();

      final session = await _sets(data, query: '?ajuste=110');
      final both = await _sets(
        data,
        query: '?ajuste=110&ajusteEjercicio=squat:90',
      );

      expect(session.first['pctAplicado'], 88);
      expect(session[3]['pctAplicado'], 55);
      expect(both.first['pctAplicado'], 72);
      expect(both[3]['pctAplicado'], 55);
    });

    test('agrees with the value later recorded for that set', () async {
      final data = _data()..factors.add(_factor('club-a', 'squat', 90));

      final proposed = (await _sets(data, query: '?ajuste=105')).first;
      final record = await _recorded(data, {
        'bloque': 0,
        'prescripcion': 0,
        'serie': 0,
        'ajuste': 105,
      });

      expect(record.kg, proposed['kilos']);
      expect(record.pctPlan, proposed['pctAplicado']);
    });

    test('a plan with no published version is unprocessable', () async {
      final data = _data()..plans.remove('club-a/p1');

      final response = await _get(data);

      expect(response.statusCode, HttpStatus.unprocessableEntity);
    });
  });

  group('what an athlete is told', () {
    test('never their work factor or real percent', () async {
      final data = _data()..factors.add(_factor('club-a', 'squat', 90));

      final response = await _get(data, club: _athlete());
      final text = await response.body();

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('factor')));
      expect(text, isNot(contains('pctReal')));
      expect(jsonDecode(text), contains('series'));
    });

    test('but the same kilos a coach sees', () async {
      final data = _data()..factors.add(_factor('club-a', 'squat', 90));

      final coach = await _sets(data);
      final athlete = await _sets(data, club: _athlete());

      expect(athlete.first['kilos'], coach.first['kilos']);
    });
  });

  group('permissions', () {
    test('an athlete of the group can ask for a present teammate', () async {
      await _sets(_data(), athleteId: 'andi', club: _athlete());
    });

    test('an athlete outside the group gets not found', () async {
      final data = _data()..groups['club-a/g1'] = ['andi'];

      final response = await _get(data, club: _athlete());

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('in a personal club an athlete only asks about themselves', () async {
      final response = await _get(
        _data(),
        athleteId: 'andi',
        club: _athlete(type: TipoClub.personal),
      );

      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('an athlete not present is unprocessable', () async {
      final response = await _get(_data(), athleteId: 'luz');

      expect(response.statusCode, HttpStatus.unprocessableEntity);
    });

    test('a session of another club is not found', () async {
      final data = _Data()..seed('club-b');

      final response = await _get(data);

      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('malformed adjustments', () {
    for (final query in [
      '?ajuste=mucho',
      '?ajuste=200',
      '?ajusteEjercicio=squat',
      '?ajusteEjercicio=squat:10',
      '?ajusteEjercicio=:105',
    ]) {
      test('$query is a bad request', () async {
        final response = await _get(_data(), query: query);

        expect(response.statusCode, HttpStatus.badRequest);
      });
    }
  });

  final isolated = _Data();
  testClubIsolation(
    'GET /clubes/{clubId}/sesiones/{sesionId}/atletas/{atletaId}/kilos-propuestos',
    endpoint: (context) =>
        proposedLoadsEndpoint(context, 's1', 'ari', store: _Store(isolated)),
    path: '/clubes/{clubId}/sesiones/s1/atletas/ari/kilos-propuestos',
    action: Accion.registrar,
    seed: (clubId, marker) {
      isolated.seed(clubId, squatId: marker);
      isolated.athletes['$clubId/u1'] = 'ari';
    },
  );
}
