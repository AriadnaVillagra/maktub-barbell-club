import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

Json _roundTrip(Json j) => jsonDecode(jsonEncode(j)) as Json;

void main() {
  blockTimeTests();
  group('Session', () {
    test('survives a JSON round trip with every field', () {
      final s = Session(
        id: 's1',
        clubId: 'c1',
        assignmentId: 'a1',
        planId: 'p1',
        cycle: 2,
        week: 3,
        day: 4,
        date: DateTime.utc(2026, 11, 9),
        presentAthleteIds: const ['u1', 'u2'],
        note: 'Buen día',
        sequence: 9,
        lastSessionChange: 4,
        auditoria: _audit,
      );
      final json = _roundTrip(s.toJson());
      final back = Session.fromJson(json);
      expect(back.toJson(), json);
      expect(json['fecha'], '2026-11-09');
      expect(back.date, DateTime.utc(2026, 11, 9));
      expect(
        [back.assignmentId, back.planId, back.cycle, back.week, back.day],
        ['a1', 'p1', 2, 3, 4],
      );
      expect(back.presentAthleteIds, ['u1', 'u2']);
      expect(back.note, 'Buen día');
      expect([back.sequence, back.lastSessionChange], [9, 4]);
    });
  });

  group('AthleteDay', () {
    test('every status round trips by its wire name', () {
      for (final st in DayStatus.values) {
        final d = AthleteDay(
          id: 'd',
          clubId: 'c',
          assignmentId: 'a',
          athleteId: 'u',
          cycle: 1,
          week: 1,
          day: 1,
          status: st,
          date: st == DayStatus.pending ? null : DateTime.utc(2026, 11, 9),
          sessionId: st == DayStatus.doneOnDate ? 's' : null,
          auditoria: _audit,
        );
        final json = _roundTrip(d.toJson());
        final back = AthleteDay.fromJson(json);
        expect(back.toJson(), json);
        expect(back.status, st);
      }
      expect(DayStatus.values.map((e) => e.cable), [
        'pendiente',
        'hecho_en_fecha',
        'recuperado',
        'falta',
      ]);
    });
  });

  group('SessionChange', () {
    final session = Session(
      id: 's1',
      clubId: 'c1',
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 1,
      week: 1,
      day: 1,
      date: DateTime.utc(2026, 11, 9),
      auditoria: _audit,
    );
    final setRecord = SetRecord(
      id: 'r',
      clubId: 'c1',
      sessionId: 's1',
      athleteId: 'u',
      exerciseId: 'e',
      exerciseName: 'x',
      blockIndex: 0,
      prescriptionIndex: 0,
      setIndex: 0,
      sequence: 3,
      writtenBy: 'u',
      auditoria: _audit,
    );

    test('a record change survives a JSON round trip', () {
      final json = _roundTrip(SessionChange.ofRecord(3, setRecord).toJson());
      final back = SessionChange.fromJson(json);

      expect(json['tipo'], 'registro');
      expect(back.toJson(), json);
      expect(back.record!.sequence, 3);
      expect([back.clubId, back.sessionId], ['c1', 's1']);
    });

    test('a session change survives a JSON round trip', () {
      final json = _roundTrip(SessionChange.ofSession(4, session).toJson());
      final back = SessionChange.fromJson(json);

      expect(json['tipo'], 'sesion');
      expect(back.toJson(), json);
      expect(back.record, isNull);
      expect([back.clubId, back.sessionId], ['c1', 's1']);
    });
  });

  group('SetRecord', () {
    SetRecord record({double? kg, RecordPcts? p, bool manual = false}) =>
        SetRecord(
          id: 'r1',
          clubId: 'c1',
          sessionId: 's1',
          athleteId: 'u1',
          exerciseId: 'e1',
          exerciseName: 'Sentadilla',
          blockIndex: 1,
          prescriptionIndex: 0,
          setIndex: 2,
          target: const PlanSet(reps: 5, pct: 80),
          kg: kg,
          reps: 5,
          seconds: 30,
          distanceM: 100,
          calories: 12,
          referenceId: 'rm1',
          referenceValue: 100,
          workFactor: 90,
          pctPlan: p?.pctPlan,
          pctReal: p?.pctReal,
          rpe: 8.5,
          manualKg: manual,
          writtenBy: 'u1',
          auditoria: _audit,
        );

    test('survives a JSON round trip with every field', () {
      final r = record(kg: 72, p: RecordPcts.fromPlan(80, workFactor: 90));
      final json = _roundTrip(r.toJson());
      final back = SetRecord.fromJson(json);
      expect(back.toJson(), json);
      expect(back.exerciseName, 'Sentadilla');
      expect(
        [back.blockIndex, back.prescriptionIndex, back.setIndex],
        [1, 0, 2],
      );
      expect(back.target.pct, 80);
      expect(back.target.reps, 5);
      expect(
        [back.referenceId, back.referenceValue, back.workFactor],
        ['rm1', 100, 90],
      );
      expect([back.pctPlan, back.pctReal, back.rpe], [80, 72, 8.5]);
      expect(back.writtenBy, 'u1');
      expect(back.done, isTrue);
    });

    test('the note survives a JSON round trip', () {
      final json = SetRecord(
        id: 'r',
        clubId: 'c',
        sessionId: 's',
        athleteId: 'u',
        exerciseId: 'e',
        exerciseName: 'x',
        blockIndex: 0,
        prescriptionIndex: 0,
        setIndex: 0,
        note: 'Liviano',
        writtenBy: 'u',
        auditoria: _audit,
      ).toJson();
      expect(json['nota'], 'Liviano');
      expect(SetRecord.fromJson(_roundTrip(json)).note, 'Liviano');
    });

    test('optional fields stay out of the JSON when absent', () {
      final json = SetRecord(
        id: 'r',
        clubId: 'c',
        sessionId: 's',
        athleteId: 'u',
        exerciseId: 'e',
        exerciseName: 'x',
        blockIndex: 0,
        prescriptionIndex: 0,
        setIndex: 0,
        writtenBy: 'u',
        auditoria: _audit,
      ).toJson();
      expect(json.containsKey('rpe'), isFalse);
      expect(json.containsKey('kilos'), isFalse);
      expect(json.containsKey('nota'), isFalse);
      expect(SetRecord.fromJson(_roundTrip(json)).rpe, isNull);
    });
  });

  group('rm × pct_real ≈ kg', () {
    final equipo = Equipo.estandar;

    for (final factor in [100.0, 90.0, 80.0]) {
      test('plan percent with factor $factor', () {
        const rm = 143.0;
        final p = proposedFromPlan(
          rm: rm,
          pctPlan: 75,
          equipo: equipo,
          workFactor: factor,
        )!;
        expect(p.pcts.pctReal, closeTo(factor * 75 / 100, 0.01));
        // The kilos are rounded to a loadable weight, so allow one step of plates.
        expect(rm * p.pcts.pctReal / 100, closeTo(p.kg, 1.25));
      });
    }

    test('typed kilos: both percents come from them', () {
      const rm = 143.0;
      final pcts = RecordPcts.fromWeight(101, rm, workFactor: 90)!;
      expect(pcts.pctReal, closeTo(101 / rm * 100, 0.01));
      expect(rm * pcts.pctReal / 100, closeTo(101, 0.01));
      expect(pcts.pctReal, closeTo(90 * pcts.pctPlan / 100, 0.02));
    });

    test('typed kilos without a usable RM give no percents', () {
      expect(RecordPcts.fromWeight(100, null), isNull);
      expect(RecordPcts.fromWeight(100, 0), isNull);
    });
  });
}

void blockTimeTests() {
  group('BlockTime', () {
    BlockTime build({AthleteMode? mode = AthleteMode.turns}) => BlockTime(
      id: 't1',
      clubId: 'c1',
      sessionId: 's1',
      blockIndex: 2,
      blockName: 'Fuerza',
      athleteMode: mode,
      athleteIds: const ['a1', 'a2'],
      start: DateTime.utc(2026, 11, 16, 18),
      end: DateTime.utc(2026, 11, 16, 18, 12, 30),
      interrupted: true,
      auditoria: _audit,
    );

    test('survives a JSON round trip with every field', () {
      final json = _roundTrip(build().toJson());
      expect(BlockTime.fromJson(json).toJson(), json);
      expect(json['modoAtletas'], 'por_turnos');
      expect(json.containsKey('segundos'), isFalse);
    });

    test('has no athlete mode when the block has no sets', () {
      final json = _roundTrip(build(mode: null).toJson());
      expect(json.containsKey('modoAtletas'), isFalse);
      expect(BlockTime.fromJson(json).athleteMode, isNull);
    });

    test('derives the seconds from start and end', () {
      expect(build().seconds, 750);
    });
  });
}
