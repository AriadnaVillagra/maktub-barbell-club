import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

Exercise _ex(
  String id, {
  List<Metric> metrics = const [Metric.loadPctRm, Metric.reps],
  List<String> categories = const ['strength'],
}) => Exercise(
  id: id,
  clubId: 'c1',
  name: id,
  metrics: metrics,
  categoryIds: categories,
  auditoria: _audit,
);

final _catalog = {
  'squat': _ex('squat'),
  'clean': _ex('clean', categories: const ['primario']),
  'stretch': _ex(
    'stretch',
    metrics: const [Metric.time],
    categories: const ['estiramiento'],
  ),
  'curl': _ex(
    'curl',
    metrics: const [Metric.fixedLoad, Metric.reps],
    categories: const ['accessory'],
  ),
  'plank': _ex(
    'plank',
    metrics: const [Metric.time],
    categories: const ['accessory'],
  ),
};

Exercise? _lookup(String id) => _catalog[id];

PlanBlock _validBlock() => const PlanBlock(
  name: 'Strength',
  categoryId: 'strength',
  prescriptions: [
    Prescription(
      exerciseId: 'squat',
      sets: [PlanSet(reps: 8, pct: 60), PlanSet(reps: 5, pct: 65)],
    ),
  ],
);

Plan _plan({
  String name = 'October',
  List<WeekModel>? models,
  List<String> assignment = const ['A', 'B', 'B', 'A'],
}) => Plan(
  id: 'p1',
  clubId: 'c1',
  name: name,
  weekModels:
      models ??
      [
        WeekModel(
          id: 'A',
          name: 'Deload',
          days: [
            PlanDay(blocks: [_validBlock()]),
          ],
        ),
        WeekModel(
          id: 'B',
          name: 'Load',
          days: [
            PlanDay(name: 'Monday', blocks: [_validBlock()]),
            PlanDay(blocks: [_validBlock()]),
          ],
        ),
      ],
  weekAssignment: assignment,
  auditoria: _audit,
);

List<PlanProblem> _validate(Plan p) => validatePlan(p, exerciseById: _lookup);

Plan _withBlock(PlanBlock block) => _plan(
  models: [
    WeekModel(
      id: 'A',
      name: 'A',
      days: [
        PlanDay(blocks: [block]),
      ],
    ),
  ],
  assignment: const ['A', 'A', 'A', 'A'],
);

void main() {
  group('wire contract', () {
    test('a plan round-trips through JSON with every field', () {
      final plan = Plan(
        id: 'p1',
        clubId: 'c1',
        name: 'Test plan',
        type: PlanType.test,
        weekModels: [
          WeekModel(
            id: 'A',
            name: 'Week A',
            days: [
              PlanDay(
                name: 'Day 1',
                blocks: [
                  PlanBlock(
                    name: 'Triset',
                    categoryId: 'accessory',
                    executionMode: ExecutionMode.circuit,
                    athleteMode: AthleteMode.turns,
                    timerId: 't90',
                    prescriptions: [
                      Prescription(
                        exerciseId: 'squat',
                        note: 'RPE 8',
                        timerId: 't180',
                        barKg: 15,
                        sets: [
                          PlanSet(
                            reps: 3,
                            maxReps: true,
                            pct: 72.5,
                            kg: 20,
                            seconds: 90,
                            distanceM: 400,
                            pctOfMark: 95,
                            paceSecPerKm: 300,
                            pacePct: 105,
                            zone: 2,
                            calories: 12,
                            attempt: 3,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        weekAssignment: const ['A', 'A', 'A', 'A'],
        auditoria: _audit,
      );
      final json = jsonDecode(jsonEncode(plan.toJson())) as Json;
      expect(Plan.fromJson(json).toJson(), json);
      expect(json['tipo'], 'test');
      final block =
          ((json['modelosSemana'] as List).first['dias'] as List)
                  .first['bloques']
                  .first
              as Map;
      expect(block['modoEjecucion'], 'circuito');
      expect(block['modoAtletas'], 'por_turnos');
      expect(block['prescripciones'].first['barraKg'], 15);
    });

    test('the bar override is absent when null and survives when present', () {
      const without = Prescription(exerciseId: 'squat');
      expect(without.toJson().containsKey('barraKg'), isFalse);
      expect(Prescription.fromJson(without.toJson()).barKg, isNull);
      final with20 = Prescription.fromJson(
        const Prescription(exerciseId: 'squat', barKg: 20).toJson(),
      );
      expect(with20.barKg, 20);
    });

    test('a minimal block defaults to sequential and simultaneous', () {
      final block = PlanBlock.fromJson({'nombre': 'Strength'});
      expect(block.executionMode, ExecutionMode.sequential);
      expect(block.athleteMode, AthleteMode.simultaneous);
      expect(block.prescriptions, isEmpty);
    });

    test('numbers arriving as int or double are accepted', () {
      final set = PlanSet.fromJson({'reps': 5.0, 'pct': 70, 'kilos': 12});
      expect(set.reps, 5);
      expect(set.pct, 70.0);
      expect(set.kg, 12.0);
    });

    test('enums have stable wire names and reject unknown ones', () {
      expect([for (final v in PlanType.values) v.cable], ['regular', 'test']);
      expect(
        [for (final v in ExecutionMode.values) v.cable],
        ['secuencial', 'circuito', 'por_tiempo'],
      );
      expect(
        [for (final v in AthleteMode.values) v.cable],
        ['simultaneo', 'por_turnos'],
      );
      expect(() => PlanType.deCable('otro'), throwsFormatException);
      expect(() => ExecutionMode.deCable('otro'), throwsFormatException);
      expect(() => AthleteMode.deCable('otro'), throwsFormatException);
    });

    test('a plan is a club document with audit and defaults to regular', () {
      final plan = Plan.fromJson(_plan().toJson()..remove('tipo'));
      expect(plan, isA<DelClub>());
      expect(plan.clubId, 'c1');
      expect(plan.type, PlanType.regular);
      expect(plan.auditoria.creadoPor, 'coach');
    });

    test('weekModelOf follows the assignment', () {
      final plan = _plan();
      expect(plan.weekModelOf(1)!.id, 'A');
      expect(plan.weekModelOf(2)!.id, 'B');
      expect(plan.weekModelOf(4)!.id, 'A');
      expect(plan.weekModelOf(0), isNull);
      expect(plan.weekModelOf(5), isNull);
    });
  });

  group('validatePlan', () {
    test('a well-formed plan has no problems', () {
      expect(_validate(_plan()), isEmpty);
    });

    test('empty name', () {
      expect(_validate(_plan(name: '  ')), [
        const PlanProblem(PlanProblemCode.nameEmpty),
      ]);
    });

    test('a week model needs 1 to 7 days', () {
      final eight = [
        for (var i = 0; i < 8; i++) PlanDay(blocks: [_validBlock()]),
      ];
      final problems = _validate(
        _plan(
          models: [
            const WeekModel(id: 'A', name: 'A'),
            WeekModel(id: 'B', name: 'B', days: eight),
          ],
        ),
      );
      expect(problems, [
        const PlanProblem(
          PlanProblemCode.weekModelWithoutDays,
          weekModelIndex: 0,
        ),
        const PlanProblem(
          PlanProblemCode.weekModelTooManyDays,
          weekModelIndex: 1,
        ),
      ]);
    });

    test('seven days is fine', () {
      final seven = [
        for (var i = 0; i < 7; i++) PlanDay(blocks: [_validBlock()]),
      ];
      final plan = _plan(
        models: [WeekModel(id: 'A', name: 'A', days: seven)],
        assignment: const ['A', 'A', 'A', 'A'],
      );
      expect(_validate(plan), isEmpty);
    });

    test('the assignment has exactly 4 positions', () {
      expect(_validate(_plan(assignment: const ['A', 'B', 'B'])), [
        const PlanProblem(PlanProblemCode.assignmentWrongLength),
      ]);
      expect(_validate(_plan(assignment: const ['A', 'B', 'B', 'A', 'A'])), [
        const PlanProblem(PlanProblemCode.assignmentWrongLength),
      ]);
    });

    test('every assignment position points to an existing model', () {
      expect(_validate(_plan(assignment: const ['A', 'Z', 'B', 'Y'])), [
        const PlanProblem(
          PlanProblemCode.assignmentUnknownModel,
          assignmentIndex: 1,
        ),
        const PlanProblem(
          PlanProblemCode.assignmentUnknownModel,
          assignmentIndex: 3,
        ),
      ]);
    });

    test('duplicated week model ids', () {
      final day = PlanDay(blocks: [_validBlock()]);
      final plan = _plan(
        models: [
          WeekModel(id: 'A', name: 'A', days: [day]),
          WeekModel(id: 'A', name: 'A2', days: [day]),
        ],
        assignment: const ['A', 'A', 'A', 'A'],
      );
      expect(_validate(plan), [
        const PlanProblem(
          PlanProblemCode.weekModelIdDuplicated,
          weekModelIndex: 1,
        ),
      ]);
    });

    test('a day without blocks', () {
      final plan = _plan(
        models: [
          WeekModel(
            id: 'A',
            name: 'A',
            days: [
              PlanDay(blocks: [_validBlock()]),
              const PlanDay(),
            ],
          ),
        ],
        assignment: const ['A', 'A', 'A', 'A'],
      );
      expect(_validate(plan), [
        const PlanProblem(
          PlanProblemCode.dayWithoutBlocks,
          weekModelIndex: 0,
          dayIndex: 1,
        ),
      ]);
    });

    test('a block without prescriptions', () {
      final problems = _validate(
        _withBlock(const PlanBlock(name: 'Empty', categoryId: 'strength')),
      );
      expect(problems, [
        const PlanProblem(
          PlanProblemCode.blockWithoutPrescriptions,
          weekModelIndex: 0,
          dayIndex: 0,
          blockIndex: 0,
        ),
      ]);
    });

    test('a block without category (replaces "day without primary")', () {
      final block = PlanBlock(
        name: 'Loose',
        prescriptions: _validBlock().prescriptions,
      );
      expect(_validate(_withBlock(block)), [
        const PlanProblem(
          PlanProblemCode.blockWithoutCategory,
          weekModelIndex: 0,
          dayIndex: 0,
          blockIndex: 0,
        ),
      ]);
    });

    test('an exercise outside the block category', () {
      const block = PlanBlock(
        name: 'Strength',
        categoryId: 'strength',
        prescriptions: [
          Prescription(exerciseId: 'curl', sets: [PlanSet(reps: 10)]),
        ],
      );
      expect(_validate(_withBlock(block)), [
        const PlanProblem(
          PlanProblemCode.exerciseOutsideBlockCategory,
          weekModelIndex: 0,
          dayIndex: 0,
          blockIndex: 0,
          prescriptionIndex: 0,
        ),
      ]);
    });

    test(
      'a prescription without exercise, or with one the catalog does not know',
      () {
        const block = PlanBlock(
          name: 'Strength',
          categoryId: 'strength',
          prescriptions: [
            Prescription(sets: [PlanSet(reps: 5, pct: 70)]),
            Prescription(
              exerciseId: 'ghost',
              sets: [PlanSet(reps: 5, pct: 70)],
            ),
          ],
        );
        expect(_validate(_withBlock(block)), [
          const PlanProblem(
            PlanProblemCode.prescriptionWithoutExercise,
            weekModelIndex: 0,
            dayIndex: 0,
            blockIndex: 0,
            prescriptionIndex: 0,
          ),
          const PlanProblem(
            PlanProblemCode.prescriptionUnknownExercise,
            weekModelIndex: 0,
            dayIndex: 0,
            blockIndex: 0,
            prescriptionIndex: 1,
          ),
        ]);
      },
    );

    test('a stretching exercise needs no sets', () {
      const block = PlanBlock(
        name: 'Stretching',
        categoryId: 'estiramiento',
        prescriptions: [Prescription(exerciseId: 'stretch')],
      );
      expect(_validate(_withBlock(block)), isEmpty);
    });

    test('a WoD block accepts exercises of any category', () {
      const block = PlanBlock(
        name: 'EMOM',
        categoryId: wodCategoryId,
        prescriptions: [
          Prescription(
            exerciseId: 'squat',
            sets: [PlanSet(reps: 8, pct: 60)],
          ),
        ],
      );
      expect(_validate(_withBlock(block)), isEmpty);
    });

    test('a prescription without sets in a block that requires them', () {
      const block = PlanBlock(
        name: 'Main',
        categoryId: 'primario',
        prescriptions: [Prescription(exerciseId: 'clean')],
      );
      expect(_validate(_withBlock(block)), [
        const PlanProblem(
          PlanProblemCode.prescriptionWithoutSets,
          weekModelIndex: 0,
          dayIndex: 0,
          blockIndex: 0,
          prescriptionIndex: 0,
        ),
      ]);
    });

    test(
      'a set without reps, and a set without % on a percentage exercise',
      () {
        const block = PlanBlock(
          name: 'Strength',
          categoryId: 'strength',
          prescriptions: [
            Prescription(
              exerciseId: 'squat',
              sets: [
                PlanSet(reps: 8, pct: 60),
                PlanSet(pct: 65),
                PlanSet(reps: 5),
                PlanSet(),
              ],
            ),
          ],
        );
        PlanProblem at(PlanProblemCode code, int s) => PlanProblem(
          code,
          weekModelIndex: 0,
          dayIndex: 0,
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: s,
        );
        expect(_validate(_withBlock(block)), [
          at(PlanProblemCode.setWithoutReps, 1),
          at(PlanProblemCode.setWithoutPct, 2),
          at(PlanProblemCode.setWithoutReps, 3),
          at(PlanProblemCode.setWithoutPct, 3),
        ]);
      },
    );

    test('max reps counts as reps, and a fixed-load exercise needs no %', () {
      const block = PlanBlock(
        name: 'Accessory',
        categoryId: 'accessory',
        prescriptions: [
          Prescription(
            exerciseId: 'curl',
            sets: [PlanSet(maxReps: true), PlanSet(reps: 10)],
          ),
        ],
      );
      expect(_validate(_withBlock(block)), isEmpty);
    });

    test('an exercise that does not measure reps needs none', () {
      const block = PlanBlock(
        name: 'Core',
        categoryId: 'accessory',
        prescriptions: [
          Prescription(exerciseId: 'plank', sets: [PlanSet(seconds: 60)]),
        ],
      );
      expect(_validate(_withBlock(block)), isEmpty);
    });

    test('the bar override must be positive when present', () {
      PlanBlock withBar(double? bar) => PlanBlock(
        name: 'Strength',
        categoryId: 'strength',
        prescriptions: [
          Prescription(
            exerciseId: 'squat',
            barKg: bar,
            sets: const [PlanSet(reps: 5, pct: 70)],
          ),
        ],
      );
      expect(_validate(_withBlock(withBar(null))), isEmpty);
      expect(_validate(_withBlock(withBar(15))), isEmpty);
      for (final bad in [0.0, -5.0]) {
        expect(_validate(_withBlock(withBar(bad))), [
          const PlanProblem(
            PlanProblemCode.prescriptionBarNotPositive,
            weekModelIndex: 0,
            dayIndex: 0,
            blockIndex: 0,
            prescriptionIndex: 0,
          ),
        ]);
      }
    });

    test('returns every problem at once, not just the first', () {
      final plan = _plan(
        name: '',
        assignment: const ['A', 'X', 'A', 'A'],
        models: [
          const WeekModel(
            id: 'A',
            name: 'A',
            days: [
              PlanDay(),
              PlanDay(blocks: [PlanBlock(name: 'Empty')]),
            ],
          ),
        ],
      );
      expect(
        [for (final p in _validate(plan)) p.code],
        [
          PlanProblemCode.nameEmpty,
          PlanProblemCode.dayWithoutBlocks,
          PlanProblemCode.blockWithoutCategory,
          PlanProblemCode.blockWithoutPrescriptions,
          PlanProblemCode.assignmentUnknownModel,
        ],
      );
    });
  });
}
