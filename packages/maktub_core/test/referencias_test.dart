import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 7));

Reference _rm(
  String id,
  DateTime date, {
  double value = 100,
  ReferenceType type = ReferenceType.rm,
  String? ex = 'squat',
}) => Reference(
  id: id,
  clubId: 'c1',
  athleteId: 'a1',
  exerciseId: ex,
  type: type,
  value: value,
  date: date,
  origin: ReferenceOrigin.testeado,
  auditoria: _audit,
);

WorkFactor _factor(String id, DateTime date, double value) => WorkFactor(
  id: id,
  clubId: 'c1',
  athleteId: 'a1',
  exerciseId: 'squat',
  value: value,
  date: date,
  auditoria: _audit,
);

double _at(List<WorkFactor> f, List<Reference> r, DateTime on) =>
    currentWorkFactor(f, r, athleteId: 'a1', exerciseId: 'squat', on: on);

void main() {
  final jan = DateTime.utc(2026, 1, 10);
  final feb = DateTime.utc(2026, 2, 10);
  final mar = DateTime.utc(2026, 3, 10);

  group('models', () {
    test('Reference round-trips through JSON with a calendar date', () {
      final r = _rm('r1', feb, value: 140.5);
      final json = r.toJson();
      expect(json['fecha'], '2026-02-10');
      expect(json['tipo'], 'rm');
      expect(json['origen'], 'testeado');
      final copy = Reference.fromJson(json);
      expect(
        (copy.athleteId, copy.exerciseId, copy.value, copy.date, copy.clubId),
        ('a1', 'squat', 140.5, feb, 'c1'),
      );
    });

    test('fc_max has no exercise, but rm requires one', () {
      final hr = _rm('h', jan, type: ReferenceType.fcMax, ex: null);
      expect(Reference.fromJson(hr.toJson()).exerciseId, isNull);
      expect(ReferenceType.deCable('fc_max'), ReferenceType.fcMax);
      expect(
        () => Reference.fromJson((_rm('x', jan, ex: null)).toJson()),
        throwsFormatException,
      );
    });

    test('WorkFactor and FixedWeight round-trip through JSON', () {
      final f = WorkFactor.fromJson(_factor('f', jan, 80).toJson());
      expect((f.value, f.date, f.exerciseId), (80, jan, 'squat'));
      final k = FixedWeight.fromJson(
        FixedWeight(
          id: 'k',
          clubId: 'c1',
          athleteId: 'a1',
          exerciseId: 'db',
          kg: 22.5,
          auditoria: _audit,
        ).toJson(),
      );
      expect((k.kg, k.exerciseId), (22.5, 'db'));
    });

    test('origins have stable wire names', () {
      expect(
        [for (final o in ReferenceOrigin.values) o.cable],
        ['testeado', 'estimado', 'importado'],
      );
      expect(
        [for (final t in ReferenceType.values) t.cable],
        ['rm', 'marca', 'ritmo', 'fc_max', 'zonas'],
      );
    });
  });

  group('currentReference', () {
    Reference? at(List<Reference> r, DateTime on) => currentReference(
      r,
      athleteId: 'a1',
      exerciseId: 'squat',
      type: ReferenceType.rm,
      on: on,
    );

    test('is the latest with date <= the queried one, or none', () {
      final refs = [_rm('a', jan), _rm('b', mar)];
      expect(at(refs, DateTime.utc(2026, 1, 9)), isNull);
      expect(at(refs, jan)!.id, 'a');
      expect(at(refs, feb)!.id, 'a');
      expect(at(refs, mar)!.id, 'b');
    });

    test('ignores other athletes, exercises and types', () {
      final refs = [
        _rm('a', jan, ex: 'bench'),
        _rm('b', jan, type: ReferenceType.marca),
      ];
      expect(at(refs, mar), isNull);
    });
  });

  group('currentWorkFactor', () {
    test('no factor is 100 %', () {
      expect(_at([], [_rm('r', jan)], feb), 100);
    });

    test('RM after the factor resets it to 100 %', () {
      expect(_at([_factor('f', jan, 80)], [_rm('r', feb)], mar), 100);
    });

    test('factor after the RM is that factor', () {
      expect(_at([_factor('f', feb, 80)], [_rm('r', jan)], mar), 80);
    });

    test('backdated RM that falls before an existing factor keeps the factor in force', () {
      final factors = [_factor('f', feb, 80)];
      expect(
        _at(factors, [
          _rm('r1', jan),
          _rm('r2', DateTime.utc(2026, 1, 20)),
        ], mar),
        80,
      );
    });

    test('backdated RM loaded later does not change what was in force before its date', () {
      final factors = [_factor('f', jan, 80)];
      final before = [_rm('r1', DateTime.utc(2026, 1, 1))];
      final withBackdated = [...before, _rm('r2', mar)];
      final on = DateTime.utc(2026, 2, 1);
      expect(_at(factors, before, on), 80);
      expect(_at(factors, withBackdated, on), 80);
      expect(_at(factors, withBackdated, mar), 100);
    });

    test('factor and RM on the same date: the factor counts', () {
      expect(_at([_factor('f', feb, 85)], [_rm('r', feb)], feb), 85);
    });

    test('a later factor after the reset applies again', () {
      final factors = [_factor('f1', jan, 80), _factor('f2', mar, 90)];
      expect(_at(factors, [_rm('r', feb)], DateTime.utc(2026, 2, 20)), 100);
      expect(_at(factors, [_rm('r', feb)], mar), 90);
    });

    test('factor with no RM in force stands', () {
      expect(_at([_factor('f', jan, 80)], [], feb), 80);
    });
  });
}
