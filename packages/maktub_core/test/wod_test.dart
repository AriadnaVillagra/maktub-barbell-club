import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

Wod _wod({
  String name = 'Fran',
  String? description,
  String? timerId,
  List<Prescription> prescriptions = const [],
}) => Wod(
  id: 'w1',
  clubId: 'c1',
  name: name,
  description: description,
  timerId: timerId,
  prescriptions: prescriptions,
  auditoria: _audit,
);

void main() {
  group('Wod JSON', () {
    test('a full WoD survives a JSON round trip', () {
      final wod = _wod(
        description: '21-15-9',
        timerId: 't1',
        prescriptions: const [
          Prescription(
            exerciseId: 'thruster',
            sets: [PlanSet(reps: 21, kg: 43), PlanSet(reps: 15, kg: 43)],
            note: 'unbroken',
            barKg: 15,
          ),
          Prescription(exerciseId: 'pullup'),
        ],
      );
      final json = jsonDecode(jsonEncode(wod.toJson())) as Map<String, dynamic>;
      final back = Wod.fromJson(json);
      expect(back.toJson(), json);
      expect(back.clubId, 'c1');
      expect(back.description, '21-15-9');
      expect(back.timerId, 't1');
      expect(back.prescriptions, hasLength(2));
      expect(back.prescriptions[1].sets, isEmpty);
    });

    test('optional fields are omitted from the JSON when null', () {
      final json = _wod().toJson();
      expect(json.containsKey('descripcion'), isFalse);
      expect(json.containsKey('temporizadorId'), isFalse);
      expect(json['prescripciones'], isEmpty);
      expect(json['nombre'], 'Fran');
    });

    test('is a club document', () {
      expect(_wod(), isA<DelClub>());
    });
  });

  group('validateWod', () {
    test('a named WoD with exercises is valid, with or without sets', () {
      expect(
        validateWod(
          _wod(prescriptions: const [Prescription(exerciseId: 'run')]),
        ),
        isEmpty,
      );
    });

    test('a WoD without prescriptions is valid', () {
      expect(validateWod(_wod()), isEmpty);
    });

    test('reports a blank name', () {
      expect(validateWod(_wod(name: '  ')), [
        const WodProblem(WodProblemCode.nameEmpty),
      ]);
    });

    test('reports each prescription without exercise, with its position', () {
      final problems = validateWod(
        _wod(
          name: '',
          prescriptions: const [
            Prescription(),
            Prescription(exerciseId: 'run'),
            Prescription(sets: [PlanSet(reps: 5)]),
          ],
        ),
      );
      expect(problems, [
        const WodProblem(WodProblemCode.nameEmpty),
        const WodProblem(
          WodProblemCode.prescriptionWithoutExercise,
          prescriptionIndex: 0,
        ),
        const WodProblem(
          WodProblemCode.prescriptionWithoutExercise,
          prescriptionIndex: 2,
        ),
      ]);
    });
  });

  group('PlanBlock note', () {
    test('is written as nota and survives a round trip', () {
      const block = PlanBlock(name: 'WoD', note: '21-15-9');
      final json = block.toJson();
      expect(json['nota'], '21-15-9');
      expect(PlanBlock.fromJson(json).note, '21-15-9');
    });

    test('is omitted from the JSON when null', () {
      expect(
        const PlanBlock(name: 'WoD').toJson().containsKey('nota'),
        isFalse,
      );
    });

    test('a block stored without the key still reads, with no note', () {
      final block = PlanBlock.fromJson({
        'nombre': 'Fuerza',
        'categoriaId': 'primario',
        'modoEjecucion': 'secuencial',
        'modoAtletas': 'simultaneo',
        'prescripciones': <Object>[],
      });
      expect(block.note, isNull);
      expect(block.name, 'Fuerza');
    });
  });
}
