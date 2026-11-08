import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/wods/domain/wod_draft.dart';

import 'fakes.dart';

void main() {
  const squat = Prescription(exerciseId: 'squat', sets: [PlanSet(reps: 10)]);
  const press = Prescription(exerciseId: 'press');

  test('starts from a WoD with all its fields', () {
    final draft = WodDraft.from(
      sampleWod(description: 'Rápido', timerId: 't1', prescriptions: [squat]),
    );
    expect(draft.name, 'Fran');
    expect(draft.description, 'Rápido');
    expect(draft.timerId, 't1');
    expect(draft.prescriptions, [squat]);
  });

  test('operations return new drafts and leave the old one alone', () {
    const base = WodDraft(name: 'A');
    final next = base
        .withName('B')
        .withDescription('d')
        .withTimer('t')
        .addPrescription(squat);
    expect(base.name, 'A');
    expect(base.prescriptions, isEmpty);
    expect(next.name, 'B');
    expect(next.description, 'd');
    expect(next.timerId, 't');
    expect(next.prescriptions, [squat]);
    expect(next.withTimer(null).timerId, isNull);
  });

  test('prescriptions are added, replaced and removed by index', () {
    final draft = const WodDraft()
        .addPrescription(squat)
        .addPrescription(press);
    expect(draft.updatePrescription(1, squat).prescriptions, [squat, squat]);
    expect(draft.removePrescription(0).prescriptions, [press]);
    expect(identical(draft.removePrescription(5), draft), isTrue);
    expect(identical(draft.updatePrescription(-1, squat), draft), isTrue);
  });

  test('reports the problems validateWod reports', () {
    final draft = const WodDraft(
      name: '  ',
      prescriptions: [squat, Prescription()],
    );
    expect(draft.problems, const [
      WodProblem(WodProblemCode.nameEmpty),
      WodProblem(
        WodProblemCode.prescriptionWithoutExercise,
        prescriptionIndex: 1,
      ),
    ]);
    expect(const WodDraft(name: 'x').problems, isEmpty);
  });

  test(
    'the body trims, leaves out a blank description and a missing timer',
    () {
      expect(const WodDraft(name: ' Fran ', description: '  ').toBody(), {
        'nombre': 'Fran',
        'prescripciones': <Object>[],
      });
      final body = WodDraft(
        name: 'Fran',
        description: ' d ',
        timerId: 't1',
        prescriptions: const [squat],
      ).toBody();
      expect(body['descripcion'], 'd');
      expect(body['temporizadorId'], 't1');
      expect(body['prescripciones'], [squat.toJson()]);
    },
  );
}
