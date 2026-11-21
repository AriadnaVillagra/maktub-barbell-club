import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

Json _roundTrip(Json j) => jsonDecode(jsonEncode(j)) as Json;

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

HistoryEntry _entry({String? planName = 'Abril 2026'}) => HistoryEntry(
  sessionId: 's1',
  date: DateTime.utc(2026, 4, 3),
  assignmentId: 'as1',
  planId: 'p1',
  planName: planName,
  planType: planName == null ? null : PlanType.history,
  cycle: 1,
  week: 2,
  day: 3,
  dayName: planName == null ? null : 'Pierna',
  done: 4,
  total: 6,
  estimated: 2,
);

void main() {
  group('HistoryEntry', () {
    test('survives a JSON round trip with every field', () {
      final json = _roundTrip(_entry().toJson());
      expect(HistoryEntry.fromJson(json).toJson(), json);
      expect(json['fecha'], '2026-04-03');
      expect(json['planTipo'], 'historico');
      expect([json['hechas'], json['total'], json['estimadas']], [4, 6, 2]);
    });

    test('a deleted plan travels without name or type', () {
      final json = _roundTrip(_entry(planName: null).toJson());
      expect(json.containsKey('planNombre'), isFalse);
      expect(json.containsKey('planTipo'), isFalse);
      final back = HistoryEntry.fromJson(json);
      expect(back.planName, isNull);
      expect(back.planType, isNull);
    });
  });

  group('HistoryPage', () {
    test('carries the next cursor only when there is more', () {
      final more = HistoryPage(entries: [_entry()], next: DateTime.utc(2026, 4, 3));
      final json = _roundTrip(more.toJson());
      expect(json['siguiente'], '2026-04-03');
      expect(HistoryPage.fromJson(json).next, DateTime.utc(2026, 4, 3));
      expect(HistoryPage.fromJson(json).entries.single.sessionId, 's1');

      final last = _roundTrip(const HistoryPage().toJson());
      expect(last.containsKey('siguiente'), isFalse);
      expect(HistoryPage.fromJson(last).next, isNull);
    });
  });

  group('SessionHistory', () {
    test('survives a JSON round trip with blocks, sets and records', () {
      final record = SetRecord(
        id: 'r1',
        clubId: 'c1',
        sessionId: 's1',
        athleteId: 'a1',
        exerciseId: 'sq',
        exerciseName: 'Sentadilla',
        blockIndex: 0,
        prescriptionIndex: 0,
        setIndex: 0,
        target: const PlanSet(reps: 5, pct: 80),
        kg: 100,
        reps: 5,
        estimated: true,
        note: 'Pesada',
        writtenBy: 'u1',
        auditoria: _audit,
      );
      final history = SessionHistory(
        entry: _entry(),
        note: 'Buen día',
        blocks: [
          HistoryBlock(
            index: 0,
            name: 'Principal',
            seconds: 900,
            interrupted: true,
            exercises: [
              HistoryExercise(
                index: 0,
                exerciseId: 'sq',
                exerciseName: 'Sentadilla',
                sets: [
                  HistorySet(index: 0, target: record.target, record: record),
                  const HistorySet(index: 1, target: PlanSet(reps: 5, pct: 85)),
                ],
              ),
            ],
          ),
        ],
      );
      final json = _roundTrip(history.toJson());
      final back = SessionHistory.fromJson(json);
      expect(back.toJson(), json);
      expect(back.note, 'Buen día');
      final block = back.blocks.single;
      expect([block.name, block.seconds, block.interrupted], ['Principal', 900, true]);
      final exercise = block.exercises.single;
      expect(exercise.note, 'Pesada');
      expect(exercise.sets.first.record!.estimated, isTrue);
      expect(exercise.sets.last.record, isNull);
      expect(exercise.sets.last.target.pct, 85);
    });

    test('a block without time or name travels without them', () {
      final json = _roundTrip(const HistoryBlock(index: 2).toJson());
      expect(json, {'bloque': 2, 'ejercicios': <Object>[]});
    });
  });
}
