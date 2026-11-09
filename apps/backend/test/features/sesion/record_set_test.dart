import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

class _FakeStore implements RecordSetStore {
  final sessions = <String, Session>{};
  final plans = <String, PublishedPlan>{};
  final athletes = <String, String>{};
  final catalog = <String, Map<String, Exercise>>{};
  final allReferences = <Reference>[];
  final allFactors = <WorkFactor>[];
  final allFixed = <FixedWeight>[];
  final equipments = <String, Equipo>{};
  final stored = <String, SetRecord>{};

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      sessions['$clubId/$sessionId'];

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async =>
      plans['$clubId/$planId'];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      athletes['$clubId/$userId'];

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async =>
      catalog[clubId] ?? const {};

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => [
    for (final r in allReferences)
      if (r.clubId == clubId &&
          r.athleteId == athleteId &&
          r.exerciseId == exerciseId)
        r,
  ];

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => [
    for (final f in allFactors)
      if (f.clubId == clubId &&
          f.athleteId == athleteId &&
          f.exerciseId == exerciseId)
        f,
  ];

  @override
  Future<FixedWeight?> fixedWeight(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async {
    for (final w in allFixed) {
      if (w.clubId == clubId &&
          w.athleteId == athleteId &&
          w.exerciseId == exerciseId) {
        return w;
      }
    }
    return null;
  }

  @override
  Future<Equipo?> equipment(String clubId) async => equipments[clubId];

  @override
  Future<SetRecord> upsert(SetRecord r, {bool keepNote = false}) async {
    final key =
        '${r.clubId}/${r.sessionId}/${r.athleteId}/${r.blockIndex}/${r.prescriptionIndex}/${r.setIndex}';
    final old = stored[key];
    final merged = SetRecord.fromJson({
      ...r.toJson(),
      if (keepNote) 'nota': old?.note,
      'id': old?.id ?? r.id,
      'auditoria': Auditoria(
        creadoPor: old?.auditoria.creadoPor ?? r.auditoria.creadoPor,
        creadoEn: old?.auditoria.creadoEn ?? r.auditoria.creadoEn,
        modificadoPor: r.auditoria.modificadoPor,
        modificadoEn: r.auditoria.modificadoEn,
      ).toJson(),
    });
    return stored[key] = merged;
  }
}

Exercise _exercise(
  String id, {
  String? name,
  LoadReference reference = const LoadReference.own(),
  double? barKg,
  String clubId = clubPlataforma,
}) => Exercise(
  id: id,
  clubId: clubId,
  name: name ?? id,
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
  id: 'rm-$exerciseId-$value',
  clubId: clubId,
  athleteId: athleteId,
  exerciseId: exerciseId,
  type: ReferenceType.rm,
  value: value,
  date: date ?? DateTime.utc(2026, 11, 1),
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

/// The plan's only day has one block with: 0 `squat` (80 %, 5 reps, 2 sets), 1 `accessory` (no %), 2 `front` (RM of
/// `squat`), 3 `barred` (16 % on a 15 kg bar).
PublishedPlan _plan() => PublishedPlan(
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
                const Prescription(
                  exerciseId: 'squat',
                  sets: [
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

_FakeStore _store({String clubId = 'club-a'}) => _FakeStore()..seed(clubId);

extension on _FakeStore {
  void seed(String clubId, {String squatName = 'Sentadilla'}) {
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
    plans['$clubId/p1'] = _plan();
    athletes['$clubId/user-ari'] = 'ari';
    catalog[clubId] = {
      'squat': _exercise('squat', name: squatName),
      'accessory': _exercise(
        'accessory',
        reference: const LoadReference.none(),
      ),
      'front': _exercise(
        'front',
        reference: const LoadReference.otherExercise('squat'),
      ),
      'barred': _exercise('barred'),
    };
    allReferences.add(_rm(clubId, 'squat', 100));
  }
}

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

var _ids = 0;

Future<Response> _put(
  _FakeStore store,
  Map<String, dynamic> body, {
  ClubContext? club,
  String sessionId = 's1',
  DateTime? now,
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'PUT',
      Uri.parse('http://localhost/clubes/club-a/sesiones/$sessionId/registros'),
      body: jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(club ?? _coach());
  return manejarErrores()(
    (c) => recordSetEndpoint(
      c,
      sessionId,
      store: store,
      newId: () => 'record-${_ids++}',
      now: () => now ?? DateTime.utc(2026, 11, 16, 10),
    ),
  )(context);
}

Future<SetRecord> _record(
  _FakeStore store,
  Map<String, dynamic> body, {
  ClubContext? club,
  DateTime? now,
}) async {
  final response = await _put(store, body, club: club, now: now);
  final text = await response.body();
  expect(response.statusCode, HttpStatus.ok, reason: text);
  return SetRecord.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

Map<String, dynamic> _body({
  String athleteId = 'ari',
  int block = 0,
  int prescription = 0,
  int set = 0,
  Map<String, dynamic> extra = const {},
}) => {
  'atletaId': athleteId,
  'bloque': block,
  'prescripcion': prescription,
  'serie': set,
  ...extra,
};

void main() {
  setUpAll(() => registerFallbackValue(_coach()));

  group('idempotence', () {
    test('repeating the same write does not create a second record', () async {
      final store = _store();

      final first = await _record(store, _body());
      final retry = await _record(
        store,
        _body(),
        now: DateTime.utc(2026, 11, 16, 11),
      );

      expect(store.stored, hasLength(1));
      expect(retry.id, first.id);
      expect(retry.kg, first.kg);
      expect(retry.auditoria.creadoEn, first.auditoria.creadoEn);
      expect(retry.auditoria.modificadoEn, DateTime.utc(2026, 11, 16, 11));
    });

    test('writes of different sets from different devices do not overwrite each other', () async {
      final store = _store();

      await _record(
        store,
        _body(extra: {'kilosManual': true, 'kilos': 70}),
        club: _athlete(),
      );
      await _record(store, _body(set: 1, extra: {'kilosManual': true, 'kilos': 75}));
      await _record(
        store,
        _body(athleteId: 'andi', extra: {'kilosManual': true, 'kilos': 50}),
      );

      expect(store.stored, hasLength(3));
      expect(
        [for (final r in store.stored.values) r.kg],
        unorderedEquals([70, 75, 50]),
      );
    });

    test('rewriting a set replaces it and can unmark it', () async {
      final store = _store();

      await _record(store, _body());
      final unmarked = await _record(store, _body(extra: {'hecha': false}));

      expect(store.stored, hasLength(1));
      expect(unmarked.done, isFalse);
    });
  });

  group('what the plan provides', () {
    test('the exercise, its name and the target come from the published plan', () async {
      final record = await _record(_store(), _body());

      expect(record.exerciseId, 'squat');
      expect(record.exerciseName, 'Sentadilla');
      expect(record.target.pct, 80);
      expect(record.target.reps, 5);
      expect(record.reps, 5);
      expect(record.writtenBy, 'coach');
      expect(record.done, isTrue);
    });

    test('what the athlete did replaces the target', () async {
      final record = await _record(
        _store(),
        _body(extra: {'reps': 3, 'segundos': 40, 'distanciaM': 100, 'calorias': 12}),
      );

      expect(record.reps, 3);
      expect(record.seconds, 40);
      expect(record.distanceM, 100);
      expect(record.calories, 12);
    });

    test('a position outside the plan is refused', () async {
      for (final body in [
        _body(block: 1),
        _body(prescription: 9),
        _body(set: 2),
      ]) {
        final store = _store();
        final response = await _put(store, body);
        expect(response.statusCode, HttpStatus.unprocessableEntity);
        expect(store.stored, isEmpty);
      }
    });

    test('a plan with no published version is refused', () async {
      final store = _store()..plans.clear();

      final response = await _put(store, _body());

      expect(response.statusCode, HttpStatus.unprocessableEntity);
    });
  });

  group('kilos resolved by the server', () {
    test('RM × % with no factor', () async {
      final record = await _record(_store(), _body());

      expect(record.kg, 80);
      expect(record.pctPlan, 80);
      expect(record.pctReal, 80);
      expect(record.referenceId, 'rm-squat-100.0');
      expect(record.referenceValue, 100);
      expect(record.workFactor, isNull);
      expect(record.manualKg, isFalse);
    });

    test('kilos a client sends without marking them manual are ignored', () async {
      final record = await _record(_store(), _body(extra: {'kilos': 999}));

      expect(record.kg, 80);
    });

    test('applies the athlete\'s work factor', () async {
      final store = _store()..allFactors.add(_factor('club-a', 'squat', 90));

      final record = await _record(store, _body());

      expect(
        record.kg,
        pesoPorPorcentaje(
          rm: 100,
          pct: 80,
          equipo: Equipo.estandar,
          workFactor: 90,
        ),
      );
      expect(record.workFactor, 90);
      expect(record.pctPlan, 80);
      expect(record.pctReal, 72);
    });

    test('applies the day adjustment, keeping the target', () async {
      final record = await _record(_store(), _body(extra: {'ajuste': 90}));

      expect(record.kg, 72.5);
      expect(record.pctPlan, 72);
      expect(record.pctReal, 72);
      expect(record.target.pct, 80);
    });

    test('uses the RM in force on the date of the session, not a later one', () async {
      final store = _store()
        ..allReferences.add(
          _rm('club-a', 'squat', 200, date: DateTime.utc(2026, 11, 20)),
        );

      final record = await _record(store, _body());

      expect(record.referenceValue, 100);
      expect(record.kg, 80);
    });

    test('an exercise that loads from another RM uses that RM', () async {
      final record = await _record(_store(), _body(prescription: 2));

      expect(record.exerciseId, 'front');
      expect(record.kg, 50);
      expect(record.referenceId, 'rm-squat-100.0');
    });

    test('the prescription bar replaces the default bar', () async {
      final store = _store()
        ..allReferences.add(_rm('club-a', 'barred', 100))
        ..equipments['club-a'] = Equipo(
          clubId: 'club-a',
          barras: const [ItemInventario(20), ItemInventario(15)],
          discos: const [ItemInventario(1.25)],
        );

      final record = await _record(store, _body(prescription: 3));

      expect(record.kg, 15);
    });

    test('without an RM there is no weight and no percent', () async {
      final store = _store()..allReferences.clear();

      final record = await _record(store, _body());

      expect(record.kg, isNull);
      expect(record.pctPlan, isNull);
      expect(record.referenceId, isNull);
    });

    test('a set with no % takes the athlete\'s fixed weight first', () async {
      final store = _store()
        ..allFixed.add(
          FixedWeight(
            id: 'k1',
            clubId: 'club-a',
            athleteId: 'ari',
            exerciseId: 'accessory',
            kg: 22.5,
            auditoria: _audit,
          ),
        );

      final record = await _record(store, _body(prescription: 1));

      expect(record.kg, 22.5);
      expect(record.pctPlan, isNull);
      expect(record.referenceId, isNull);
    });

    test('a set with no % and no fixed weight takes the kilos of the plan', () async {
      final record = await _record(_store(), _body(prescription: 1));

      expect(record.kg, 10);
    });
  });

  group('manual kilos', () {
    test('both percents follow from the typed weight', () async {
      final store = _store()..allFactors.add(_factor('club-a', 'squat', 80));

      final record = await _record(
        store,
        _body(extra: {'kilosManual': true, 'kilos': 72}),
      );

      expect(record.kg, 72);
      expect(record.manualKg, isTrue);
      expect(record.pctPlan, 90);
      expect(record.pctReal, 72);
      expect(record.workFactor, 80);
      expect(record.referenceValue, 100);
    });

    test('no RM: the weight stays and there are no percents', () async {
      final store = _store()..allReferences.clear();

      final record = await _record(
        store,
        _body(extra: {'kilosManual': true, 'kilos': 72}),
      );

      expect(record.kg, 72);
      expect(record.pctPlan, isNull);
    });

    test('a set with no % keeps the weight without percents', () async {
      final record = await _record(
        _store(),
        _body(prescription: 1, extra: {'kilosManual': true, 'kilos': 15}),
      );

      expect(record.kg, 15);
      expect(record.pctPlan, isNull);
      expect(record.referenceId, isNull);
    });

    test('marking them manual without kilos is a bad request', () async {
      final response = await _put(
        _store(),
        _body(extra: {'kilosManual': true}),
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('who writes', () {
    test('a present athlete writes for a present teammate', () async {
      final record = await _record(
        _store(),
        _body(athleteId: 'andi'),
        club: _athlete(),
      );

      expect(record.athleteId, 'andi');
      expect(record.writtenBy, 'user-ari');
    });

    test('an athlete who is not present cannot write', () async {
      final store = _store()..athletes['club-a/user-ari'] = 'stranger';

      final response = await _put(store, _body(), club: _athlete());

      expect(response.statusCode, HttpStatus.forbidden);
      expect(store.stored, isEmpty);
    });

    test('a user with no athlete in the club cannot write', () async {
      final store = _store()..athletes.clear();

      final response = await _put(store, _body(), club: _athlete());

      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('in a personal club only for themselves', () async {
      final store = _store();

      final response = await _put(
        store,
        _body(athleteId: 'andi'),
        club: _athlete(type: TipoClub.personal),
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(store.stored, isEmpty);
    });

    test('nobody writes for an athlete who is not present', () async {
      final store = _store();

      final response = await _put(store, _body(athleteId: 'stranger'));

      expect(response.statusCode, HttpStatus.unprocessableEntity);
      expect(store.stored, isEmpty);
    });

    test('a session of another club is not found', () async {
      final store = _store(clubId: 'club-b');

      final response = await _put(store, _body());

      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('work factor visibility', () {
    Future<Map<String, dynamic>> written(ClubContext club) async {
      final store = _store()..allFactors.add(_factor('club-a', 'squat', 90));
      final response = await _put(store, _body(), club: club);
      return jsonDecode(await response.body()) as Map<String, dynamic>;
    }

    test('an athlete gets the kilos and not the factor', () async {
      final json = await written(_athlete());

      expect(json, isNot(contains('factor')));
      expect(json, isNot(contains('pctReal')));
      expect(json['kilos'], isNotNull);
    });

    test('the stored record keeps it even when an athlete writes', () async {
      final store = _store()..allFactors.add(_factor('club-a', 'squat', 90));

      await _put(store, _body(), club: _athlete());

      expect(store.stored.values.single.workFactor, 90);
      expect(store.stored.values.single.pctReal, 72);
    });

    test('the coach gets it', () async {
      final json = await written(_coach());

      expect(json['factor'], 90);
      expect(json['pctReal'], 72);
    });
  });

  group('the note', () {
    test('is stored with the record', () async {
      final record = await _record(_store(), _body(extra: {'nota': ' Liviano '}));

      expect(record.note, 'Liviano');
    });

    test('marking the set again without it does not lose it', () async {
      final store = _store();
      await _record(store, _body(extra: {'hecha': false, 'nota': 'Liviano'}));

      final record = await _record(store, _body());

      expect(record.done, isTrue);
      expect(record.note, 'Liviano');
    });

    test('an empty one clears it', () async {
      final store = _store();
      await _record(store, _body(extra: {'nota': 'Liviano'}));

      final record = await _record(store, _body(extra: {'nota': ''}));

      expect(record.note, isNull);
    });

    for (final (name, note) in [
      ('that is not text', 5),
      ('that is too long', 'x' * (maxNoteLength + 1)),
    ]) {
      test('one $name is a bad request', () async {
        final store = _store();

        final response = await _put(store, _body(extra: {'nota': note}));

        expect(response.statusCode, HttpStatus.badRequest);
        expect(store.stored, isEmpty);
      });
    }
  });

  group('malformed bodies', () {
    for (final (name, body) in [
      ('without an athlete', {'bloque': 0, 'prescripcion': 0, 'serie': 0}),
      ('without a position', {'atletaId': 'ari'}),
      ('with a negative position', _body(set: -1)),
      ('with negative kilos', _body(extra: {'kilosManual': true, 'kilos': -1})),
      ('with text as reps', _body(extra: {'reps': 'five'})),
      ('with an RPE out of range', _body(extra: {'rpe': 11})),
      ('with an RPE that is not a half', _body(extra: {'rpe': 7.3})),
    ]) {
      test('$name is a bad request', () async {
        final store = _store();

        final response = await _put(store, body);

        expect(response.statusCode, HttpStatus.badRequest);
        expect(store.stored, isEmpty);
      });
    }

    test('an RPE in range is stored', () async {
      final record = await _record(_store(), _body(extra: {'rpe': 8.5}));

      expect(record.rpe, 8.5);
    });
  });

  final isolated = _FakeStore();
  testClubIsolation(
    'PUT /clubes/{clubId}/sesiones/{sesionId}/registros',
    endpoint: (context) => recordSetEndpoint(context, 's1', store: isolated),
    path: '/clubes/{clubId}/sesiones/s1/registros',
    action: Accion.registrar,
    method: 'PUT',
    body: jsonEncode(_body()),
    seed: (clubId, marker) {
      isolated.seed(clubId, squatName: marker);
      isolated.athletes['$clubId/u1'] = 'ari';
    },
  );
}
