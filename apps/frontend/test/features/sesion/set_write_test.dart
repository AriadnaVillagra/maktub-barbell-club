import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

final _audit = Auditoria.nueva('u', ahora: DateTime.utc(2026, 11, 1));

SetRecord _record({
  bool done = false,
  bool manualKg = false,
  double kg = 80,
  int reps = 5,
}) => SetRecord(
  id: 'r',
  clubId: 'c',
  sessionId: 's',
  athleteId: 'ari',
  exerciseId: 'sq',
  exerciseName: 'Sentadilla',
  blockIndex: 0,
  prescriptionIndex: 1,
  setIndex: 2,
  target: const PlanSet(reps: 5, pct: 80),
  done: done,
  kg: kg,
  reps: reps,
  manualKg: manualKg,
  writtenBy: 'u',
  auditoria: _audit,
);

SetWrite _writeOf(SetRecord? r) => SetWrite.of(
  r,
  athleteId: 'ari',
  blockIndex: 0,
  prescriptionIndex: 1,
  setIndex: 2,
  adjustment: 105,
);

const _proposed = ProposedSet(
  blockIndex: 0,
  prescriptionIndex: 1,
  setIndex: 2,
  exerciseId: 'sq',
  kg: 90,
);

void main() {
  group('the body of a write', () {
    test('a first mark carries its position and adjustment, and no kilos', () {
      expect(_writeOf(null).toggled().toJson(), {
        'atletaId': 'ari',
        'bloque': 0,
        'prescripcion': 1,
        'serie': 2,
        'hecha': true,
        'ajuste': 105,
      });
    });

    test('typed kilos go as manual', () {
      final json = _writeOf(null).edited(manualKg: 72.5, reps: 3).toJson();

      expect(json['kilosManual'], isTrue);
      expect(json['kilos'], 72.5);
      expect(json['reps'], 3);
    });

    test('marking keeps the typed values of the record', () {
      final json = _writeOf(_record(manualKg: true, kg: 72.5, reps: 3))
          .toggled()
          .toJson();

      expect([json['hecha'], json['kilos'], json['reps']], [true, 72.5, 3]);
    });

    test('restoring drops the typed values and keeps the mark', () {
      final json = _writeOf(
        _record(done: true, manualKg: true, kg: 72.5, reps: 3),
      ).restored().toJson();

      expect(json['hecha'], isTrue);
      expect(json, isNot(contains('kilosManual')));
      expect(json, isNot(contains('kilos')));
      expect(json, isNot(contains('reps')));
    });

    test('without a note the key stays out, so the stored one is kept', () {
      expect(_writeOf(_record()).toggled().toJson(), isNot(contains('nota')));
      expect(_writeOf(_record()).withNote('').toJson()['nota'], '');
    });
  });

  group('what counts as edited', () {
    test('neither the plan values nor a mark are', () {
      expect(setIsEdited(_record(done: true)), isFalse);
    });

    test('typed kilos or other reps are', () {
      expect(setIsEdited(_record(manualKg: true)), isTrue);
      expect(setIsEdited(_record(reps: 3)), isTrue);
    });
  });

  group('the kilos shown', () {
    test('without a record, the proposal', () {
      expect(shownKg(null, _proposed), 90);
    });

    test('an unmarked record that was not typed follows the proposal', () {
      expect(shownKg(_record(kg: 80), _proposed), 90);
    });

    test('a marked or typed set keeps its kilos', () {
      expect(shownKg(_record(done: true, kg: 80), _proposed), 80);
      expect(shownKg(_record(manualKg: true, kg: 72), _proposed), 72);
    });

    test(
      'a set marked without signal shows the proposal until the server answers',
      () {
        final queued = projectedRecord(
          null,
          SetWrite.of(
            null,
            athleteId: 'ari',
            blockIndex: 0,
            prescriptionIndex: 1,
            setIndex: 2,
            adjustment: 0,
          ).toggled(),
          clubId: 'c',
          sessionId: 's',
        );
        expect(queued.done, isTrue);
        expect(shownKg(queued, _proposed), 90);
      },
    );
  });

  group('what a queued write leaves', () {
    SetWrite writeOf(SetRecord r) => SetWrite.of(
      r,
      athleteId: 'ari',
      blockIndex: 0,
      prescriptionIndex: 1,
      setIndex: 2,
      adjustment: 5,
    );

    test('keeps what the record had and applies the write', () {
      final r = projectedRecord(
        _record(),
        writeOf(_record()).edited(manualKg: 72.5, reps: 3).withNote('pesada'),
        clubId: 'c',
        sessionId: 's',
      );
      expect(
        [r.exerciseId, r.kg, r.reps, r.manualKg, r.note],
        ['sq', 72.5, 3, true, 'pesada'],
      );
    });

    test('back to the plan takes the planned reps and drops typed kilos', () {
      final typed = _record(manualKg: true, kg: 72, reps: 3);
      final r = projectedRecord(
        typed,
        writeOf(typed).restored(),
        clubId: 'c',
        sessionId: 's',
      );
      expect([r.kg, r.reps, r.manualKg], [null, 5, false]);
    });

    test('a write reads back as it was sent', () {
      final w = writeOf(_record())
          .edited(manualKg: 72.5, reps: 3)
          .withNote('')
          .toggled();
      expect(SetWrite.fromJson(w.toJson()).toJson(), w.toJson());
    });
  });
}
