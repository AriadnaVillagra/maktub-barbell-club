import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_session.dart';

final _t0 = DateTime.utc(2026, 11, 18, 10);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

const _two = [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)];

const _day = PlanDay(
  blocks: [
    // 0: no sets, done as a whole.
    PlanBlock(name: 'Movilidad', categoryId: 'estiramiento', note: 'Hombros'),
    // 1: two sets, by turns by default.
    PlanBlock(
      name: 'Principal',
      categoryId: 'primario',
      athleteMode: AthleteMode.turns,
      prescriptions: [Prescription(exerciseId: 'sq', sets: _two)],
    ),
    // 2: a circuit of two exercises, simultaneous.
    PlanBlock(
      name: 'Accesorios',
      categoryId: 'accesorio',
      executionMode: ExecutionMode.circuit,
      prescriptions: [
        Prescription(exerciseId: 'curl', sets: _two),
        Prescription(exerciseId: 'face', sets: _two),
      ],
    ),
    // 3: a timed WoD.
    PlanBlock(
      name: 'Cindy',
      categoryId: 'wod',
      executionMode: ExecutionMode.timed,
      prescriptions: [
        Prescription(exerciseId: 'pu', sets: [PlanSet(reps: 5)]),
      ],
    ),
  ],
);

const Set<BlockSet> _none = {};

/// The guided mode with Ari and Andi on the preview of block [block].
GuidedSession _onBlock(int block) {
  var g = GuidedSession.choosing(
    _day,
    const ['ari'],
  ).toggleAthlete('andi').begin(now: _t0);
  for (var b = 0; b < block; b++) {
    g = g.skipBlock(now: _t0);
  }
  return g;
}

GuidedStep _step(int p, int s, List<String> athletes) =>
    GuidedStep(prescription: p, set: s, athleteIds: athletes);

void main() {
  group('athletes', () {
    test('starts with the chosen athlete, others are added in order', () {
      final g = GuidedSession.choosing(_day, const ['ari']);
      expect(g.phase, GuidedPhase.athletes);
      expect(g.toggleAthlete('andi').athleteIds, ['ari', 'andi']);
      expect(g.toggleAthlete('ari').athleteIds, isEmpty);
    });

    test('nobody chosen cannot begin', () {
      final g = GuidedSession.choosing(_day, const []).begin(now: _t0);
      expect(g.phase, GuidedPhase.athletes);
    });

    test('begin shows the first block, with each block\'s default mode', () {
      final g = _onBlock(0);
      expect(g.phase, GuidedPhase.blocks);
      expect(g.current, 0);
      expect(g.runs.map((r) => r.athleteMode), [
        AthleteMode.simultaneous,
        AthleteMode.turns,
        AthleteMode.simultaneous,
        AthleteMode.simultaneous,
      ]);
      expect(g.runs.every((r) => r.status == GuidedBlockStatus.pending), true);
      expect(g.start, isNull);
    });

    test('a day without blocks finishes at once', () {
      final g = GuidedSession.choosing(
        const PlanDay(),
        const ['ari'],
      ).begin(now: _t0);
      expect(g.phase, GuidedPhase.finished);
    });
  });

  group('blocks', () {
    test('which ones have steps', () {
      expect(_day.blocks.map(blockHasSteps), [false, true, true, false]);
    });

    test('the mode is offered only with two athletes and a block with sets', () {
      expect(_onBlock(0).offersAthleteMode, false);
      expect(_onBlock(1).offersAthleteMode, true);
      expect(
        GuidedSession.choosing(
          _day,
          const ['ari'],
        ).begin(now: _t0).skipBlock(now: _t0).offersAthleteMode,
        false,
      );
    });

    test('a block without steps is finished whole and records its times', () {
      final g = _onBlock(0)
          .startBlock(_none, now: _at(1))
          .finishBlock(now: _at(4));
      final run = g.runs[0];
      expect(run.status, GuidedBlockStatus.done);
      expect(run.start, _at(1));
      expect(run.end, _at(4));
      expect(g.start, _at(1));
      expect(g.current, 1);
    });

    test('skipping a block leaves it without times and goes on', () {
      final g = _onBlock(0).skipBlock(now: _at(1));
      expect(g.runs[0].status, GuidedBlockStatus.skipped);
      expect(g.runs[0].start, isNull);
      expect(g.current, 1);
      expect(g.start, isNull);
    });

    test('interrupting closes the block as interrupted', () {
      final g = _onBlock(1)
          .startBlock(_none, now: _at(1))
          .interruptBlock(now: _at(3));
      expect(g.runs[1].status, GuidedBlockStatus.interrupted);
      expect(g.runs[1].end, _at(3));
      expect(g.current, 2);
    });

    test('the total time runs from the first block started to the last closed', () {
      var g = _onBlock(2).startBlock(_none, now: _at(5));
      expect(g.elapsed(_at(7)), const Duration(minutes: 2));
      g = g.interruptBlock(now: _at(8)).startBlock(_none, now: _at(9));
      g = g.finishBlock(now: _at(12));
      expect(g.phase, GuidedPhase.finished);
      expect(g.end, _at(12));
      expect(g.elapsed(_at(30)), const Duration(minutes: 7));
    });
  });

  group('steps', () {
    test('by turns, the athletes alternate set by set', () {
      final g = _onBlock(1).startBlock(_none, now: _t0);
      expect(g.pending(_none), [
        _step(0, 0, ['ari']),
        _step(0, 0, ['andi']),
        _step(0, 1, ['ari']),
        _step(0, 1, ['andi']),
      ]);
      expect(g.currentStep(_none), _step(0, 0, ['ari']));
    });

    test('simultaneous, every athlete does the step at once', () {
      final g = _onBlock(2).startBlock(_none, now: _t0);
      expect(g.pending(_none), [
        _step(0, 0, ['ari', 'andi']),
        _step(1, 0, ['ari', 'andi']),
        _step(0, 1, ['ari', 'andi']),
        _step(1, 1, ['ari', 'andi']),
      ]);
    });

    test('no step is on screen before the block starts', () {
      expect(_onBlock(1).currentStep(_none), isNull);
    });

    test('finishing a step records everyone in it and moves on', () {
      final g = _onBlock(2).startBlock(_none, now: _t0).startStep(_none);
      expect(g.draftFor(g.currentStep(_none)!).running, true);
      final r = g.finishStep(_none, now: _t0);
      expect(r.record, ['ari', 'andi']);
      expect(r.next.currentStep(_none), _step(1, 0, ['ari', 'andi']));
      expect(r.next.draftFor(r.next.currentStep(_none)!).running, false);
    });

    test('"No hizo esta serie" leaves that athlete out of the writes, and is not offered again', () {
      final g = _onBlock(2)
          .startBlock(_none, now: _t0)
          .toggleNotDone('andi', _none);
      final r = g.finishStep(_none, now: _t0);
      expect(r.record, ['ari']);
      expect(r.next.pending(_none).first, _step(1, 0, ['ari', 'andi']));
      expect(r.next.pending(_none), hasLength(3));
    });

    test('"No hizo esta serie" toggles back', () {
      final g = _onBlock(2)
          .startBlock(_none, now: _t0)
          .toggleNotDone('andi', _none)
          .toggleNotDone('andi', _none);
      expect(g.finishStep(_none, now: _t0).record, ['ari', 'andi']);
    });

    test('what is typed stays with the step', () {
      final g = _onBlock(2)
          .startBlock(_none, now: _t0)
          .edit('ari', const SetEdit(manualKg: 30, reps: 8), _none);
      final edit = g.draftFor(g.currentStep(_none)!).edits['ari']!;
      expect(edit.manualKg, 30);
      expect(edit.reps, 8);
      final next = g.finishStep(_none, now: _t0).next;
      expect(next.draftFor(next.currentStep(_none)!).edits, isEmpty);
    });

    test('leaving the exercise drops what that athlete has left of it', () {
      final g = _onBlock(1)
          .startBlock(_none, now: _t0)
          .leaveExercise('ari', _none, now: _t0);
      expect(g.pending(_none), [
        _step(0, 0, ['andi']),
        _step(0, 1, ['andi']),
      ]);
    });

    test('skipping the exercise drops it for everyone', () {
      final g = _onBlock(2)
          .startBlock(_none, now: _t0)
          .skipExercise(_none, now: _t0);
      expect(g.pending(_none), [
        _step(1, 0, ['ari', 'andi']),
        _step(1, 1, ['ari', 'andi']),
      ]);
    });

    test('the block closes as done after its last step', () {
      var g = _onBlock(1).startBlock(_none, now: _at(1));
      for (var i = 0; i < 4; i++) {
        g = g.finishStep(_none, now: _at(2 + i)).next;
      }
      expect(g.runs[1].status, GuidedBlockStatus.done);
      expect(g.runs[1].end, _at(5));
      expect(g.current, 2);
    });

    test('leaving the last exercise closes the block', () {
      final g = _onBlock(1)
          .startBlock(_none, now: _t0)
          .leaveExercise('ari', _none, now: _t0)
          .leaveExercise('andi', _none, now: _at(1));
      expect(g.runs[1].status, GuidedBlockStatus.done);
      expect(g.current, 2);
    });
  });

  group('what is already recorded', () {
    test('a set recorded for every athlete of a step skips the step', () {
      final recorded = <BlockSet>{
        (1, const AthleteSet('ari', 0, 0)),
        (1, const AthleteSet('andi', 0, 0)),
        (2, const AthleteSet('ari', 0, 1)), // another block: no effect
      };
      final g = _onBlock(1).startBlock(recorded, now: _t0);
      expect(g.currentStep(recorded), _step(0, 1, ['ari']));
    });

    test('in a simultaneous step, an athlete who recorded it drops out of it', () {
      final recorded = <BlockSet>{(2, const AthleteSet('ari', 0, 0))};
      final g = _onBlock(2).startBlock(recorded, now: _t0);
      expect(g.currentStep(recorded), _step(0, 0, ['andi']));
    });

    test('a block already recorded whole closes when it starts', () {
      final recorded = <BlockSet>{
        for (final a in ['ari', 'andi'])
          for (var s = 0; s < 2; s++) (1, AthleteSet(a, 0, s)),
      };
      final g = _onBlock(1).startBlock(recorded, now: _at(1));
      expect(g.runs[1].status, GuidedBlockStatus.done);
      expect(g.current, 2);
    });

    test('settle closes the block once another device recorded what was left', () {
      final g = _onBlock(1).startBlock(_none, now: _t0);
      expect(g.settle(_none, now: _at(1)).current, 1);
      final recorded = <BlockSet>{
        for (final a in ['ari', 'andi'])
          for (var s = 0; s < 2; s++) (1, AthleteSet(a, 0, s)),
      };
      final settled = g.settle(recorded, now: _at(1));
      expect(settled.runs[1].status, GuidedBlockStatus.done);
      expect(settled.current, 2);
    });

    test('a block without steps is never closed by settle', () {
      final g = _onBlock(0).startBlock(_none, now: _t0);
      expect(g.settle(_none, now: _at(1)).current, 0);
    });

    test('recordedSets keeps only the done sets', () {
      SetRecord r(String a, int s, {bool done = true}) => SetRecord(
        id: '$a$s',
        clubId: 'c1',
        sessionId: 's1',
        athleteId: a,
        exerciseId: 'sq',
        exerciseName: 'Sentadilla',
        blockIndex: 1,
        prescriptionIndex: 0,
        setIndex: s,
        done: done,
        writtenBy: 'u1',
        auditoria: Auditoria.nueva('u1'),
      );
      expect(recordedSets([r('ari', 0), r('andi', 0, done: false)]), {
        (1, const AthleteSet('ari', 0, 0)),
      });
    });
  });

  group('switching the athlete mode mid-block', () {
    test('turns to simultaneous groups what is left; what was done stays', () {
      var g = _onBlock(1).startBlock(_none, now: _t0);
      g = g.finishStep(_none, now: _t0).next; // Ari, set 1
      g = g.withAthleteMode(AthleteMode.simultaneous);
      expect(g.runs[1].athleteMode, AthleteMode.simultaneous);
      expect(g.pending(_none), [
        _step(0, 0, ['andi']),
        _step(0, 1, ['ari', 'andi']),
      ]);
    });

    test('simultaneous to turns splits what is left', () {
      var g = _onBlock(2).startBlock(_none, now: _t0);
      g = g.finishStep(_none, now: _t0).next;
      g = g.withAthleteMode(AthleteMode.turns);
      expect(g.pending(_none).take(3), [
        _step(1, 0, ['ari']),
        _step(1, 0, ['andi']),
        _step(0, 1, ['ari']),
      ]);
    });

    test('the mode chosen in the preview is the one the block starts with', () {
      final g = _onBlock(1)
          .withAthleteMode(AthleteMode.simultaneous)
          .startBlock(_none, now: _t0);
      expect(g.currentStep(_none), _step(0, 0, ['ari', 'andi']));
    });

    test('a closed block keeps the mode it ended with', () {
      final g = _onBlock(1).withAthleteMode(AthleteMode.simultaneous).skipBlock(
        now: _t0,
      );
      expect(g.runs[1].athleteMode, AthleteMode.simultaneous);
      expect(g.runs[2].athleteMode, AthleteMode.simultaneous);
    });
  });
}
