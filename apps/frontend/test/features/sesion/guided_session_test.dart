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
      expect(g.start, _t0, reason: 'the day runs from "Comenzar"');
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
      expect(g.start, _t0);
      expect(g.current, 1);
    });

    test('skipping a block leaves it without times and goes on', () {
      final g = _onBlock(0).skipBlock(now: _at(1));
      expect(g.runs[0].status, GuidedBlockStatus.skipped);
      expect(g.runs[0].start, isNull);
      expect(g.current, 1);
      expect(g.start, _t0);
    });

    test('a pass going on for more than three hours looks left open', () {
      final g = _onBlock(1).startBlock(_none, now: _at(1));
      expect(g.isStaleAt(_at(180)), false);
      expect(g.isStaleAt(_at(181)), true);
      expect(g.finishDay(now: _at(200)).isStaleAt(_at(300)), false);
      expect(
        GuidedSession.choosing(_day, const ['ari']).isStaleAt(_at(300)),
        false,
      );
    });

    test('interrupting closes the block as interrupted', () {
      final g = _onBlock(1)
          .startBlock(_none, now: _at(1))
          .interruptBlock(now: _at(3));
      expect(g.runs[1].status, GuidedBlockStatus.interrupted);
      expect(g.runs[1].end, _at(3));
      expect(g.current, 2);
    });

    test('the total time runs from "Comenzar" to the last block closed', () {
      var g = _onBlock(2);
      expect(g.elapsed(_at(3)), const Duration(minutes: 3));
      g = g.startBlock(_none, now: _at(5));
      expect(g.elapsed(_at(7)), const Duration(minutes: 7));
      g = g.interruptBlock(now: _at(8)).startBlock(_none, now: _at(9));
      g = g.finishBlock(now: _at(12));
      expect(g.phase, GuidedPhase.finished);
      expect(g.end, _at(12));
      expect(g.elapsed(_at(30)), const Duration(minutes: 12));
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

  group('switching sequential or circuit (E7.22)', () {
    const day = PlanDay(
      blocks: [
        // 0: sequential with two exercises.
        PlanBlock(
          name: 'Biserie',
          categoryId: 'accesorio',
          prescriptions: [
            Prescription(exerciseId: 'a', sets: _two),
            Prescription(exerciseId: 'b', sets: _two),
          ],
        ),
        // 1: one prescription with sets, another without.
        PlanBlock(
          name: 'Una',
          categoryId: 'primario',
          prescriptions: [
            Prescription(exerciseId: 'a', sets: _two),
            Prescription(exerciseId: 'b'),
          ],
        ),
        // 2: no sets.
        PlanBlock(name: 'Nota', categoryId: 'estiramiento'),
      ],
    );

    GuidedSession on(int block) {
      var g = GuidedSession.choosing(day, const ['ari']).begin(now: _t0);
      for (var b = 0; b < block; b++) {
        g = g.skipBlock(now: _t0);
      }
      return g;
    }

    List<(int, int)> order(GuidedSession g, [Set<BlockSet> rec = _none]) => [
      for (final s in g.pending(rec)) (s.prescription, s.set),
    ];

    test('a sequential block starts sequential and can be done as a circuit', () {
      var g = on(0);
      expect(g.runs[0].executionMode, ExecutionMode.sequential);
      expect(g.offersExecutionMode, isTrue);
      g = g.startBlock(_none, now: _t0);
      expect(order(g), [(0, 0), (0, 1), (1, 0), (1, 1)]);
      g = g.withExecutionMode(ExecutionMode.circuit);
      expect(order(g), [(0, 0), (1, 0), (0, 1), (1, 1)]);
    });

    test('the mode chosen in the preview is the one the block starts with', () {
      final g = on(
        0,
      ).withExecutionMode(ExecutionMode.circuit).startBlock(_none, now: _t0);
      expect(order(g), [(0, 0), (1, 0), (0, 1), (1, 1)]);
    });

    test('mid-block: what was done stays and it goes on with B1', () {
      var g = on(0).startBlock(_none, now: _t0);
      final done = <BlockSet>{(0, const AthleteSet('ari', 0, 0))};
      g = g.withExecutionMode(ExecutionMode.circuit);
      expect(order(g, done), [(1, 0), (0, 1), (1, 1)]);
      expect(g.currentStep(done), _step(1, 0, ['ari']));
      // And back to sequential: A2 comes before B1 again.
      g = g.withExecutionMode(ExecutionMode.sequential);
      expect(order(g, done), [(0, 1), (1, 0), (1, 1)]);
    });

    test('a circuit block of the plan can be done sequentially', () {
      final g = _onBlock(2).withExecutionMode(ExecutionMode.sequential);
      expect(g.runs[2].executionMode, ExecutionMode.sequential);
      expect(g.runs[2].athleteMode, AthleteMode.simultaneous);
    });

    test('one prescription with sets, or none, offers no choice', () {
      expect(on(1).offersExecutionMode, isFalse);
      expect(on(2).offersExecutionMode, isFalse);
      final same = on(1);
      expect(
        same.withExecutionMode(ExecutionMode.circuit).runs[0].executionMode,
        ExecutionMode.sequential,
      );
    });

    test('the plan and a timed block stay as they are', () {
      final g = _onBlock(3);
      expect(g.offersExecutionMode, isFalse);
      expect(
        g.withExecutionMode(ExecutionMode.circuit).runs[3].executionMode,
        ExecutionMode.timed,
      );
      expect(day.blocks[0].executionMode, ExecutionMode.sequential);
    });
  });

  group('redoing the day (E7.23)', () {
    final recorded = <BlockSet>{
      for (final a in ['ari', 'andi'])
        for (var s = 0; s < 2; s++) (1, AthleteSet(a, 0, s)),
    };

    GuidedSession redoOn(int block) {
      var g = GuidedSession.choosing(
        _day,
        const ['ari', 'andi'],
      ).begin(now: _t0, redo: true);
      for (var b = 0; b < block; b++) {
        g = g.skipBlock(now: _t0);
      }
      return g;
    }

    test('every set is offered even if recorded, and the block does not close', () {
      final g = redoOn(1).startBlock(recorded, now: _t0);
      expect(g.runs[1].status, GuidedBlockStatus.running);
      expect(g.pending(recorded), hasLength(4));
      expect(g.currentStep(recorded), _step(0, 0, ['ari']));
    });

    test('a simultaneous step has all the athletes', () {
      final rec = <BlockSet>{(2, const AthleteSet('ari', 0, 0))};
      final g = redoOn(2).startBlock(rec, now: _t0);
      expect(g.currentStep(rec), _step(0, 0, ['ari', 'andi']));
    });

    test('only what this run passed counts as done', () {
      var g = redoOn(1).startBlock(recorded, now: _t0);
      g = g.finishStep(recorded, now: _t0).next;
      expect(g.currentStep(recorded), _step(0, 0, ['andi']));
      expect(g.settle(recorded, now: _t0).current, 1);
    });

    test('without redo, recorded sets are skipped as before', () {
      final g = _onBlock(1).startBlock(recorded, now: _t0);
      expect(g.runs[1].status, GuidedBlockStatus.done);
    });

    test('recordedOfAthletes keeps only the chosen athletes', () {
      expect(recordedOfAthletes(recorded, ['ari']), {
        (1, const AthleteSet('ari', 0, 0)),
        (1, const AthleteSet('ari', 0, 1)),
      });
      expect(recordedOfAthletes(recorded, ['luz']), isEmpty);
    });
  });

  group('the shared pass (E7.26)', () {
    test('entering with a pass going on resumes it; a finished one or none chooses', () {
      final going = _onBlock(1).pass!;
      final resumed = GuidedSession.entering(_day, going, const ['luz']);
      expect(resumed.phase, GuidedPhase.blocks);
      expect(resumed.current, 1);
      expect(resumed.athleteIds, ['ari', 'andi']);

      final finished = _onBlock(0).finishDay(now: _t0).pass!;
      final again = GuidedSession.entering(_day, finished, const ['luz']);
      expect(again.phase, GuidedPhase.athletes);
      expect(again.athleteIds, ['luz']);
      expect(
        GuidedSession.entering(_day, null, const ['ari']).phase,
        GuidedPhase.athletes,
      );
    });

    test('while choosing, a pass another device begins is joined', () {
      final choosing = GuidedSession.choosing(_day, const ['ari']);
      final other = _onBlock(2).pass!;

      final joined = choosing.withPass(other);

      expect(joined.phase, GuidedPhase.blocks);
      expect(joined.current, 2);
    });

    test(
      'starting over keeps the pass until "Comenzar", which replaces it',
      () {
        final going = _onBlock(1);
        final over = going.startingOver();
        expect(over.phase, GuidedPhase.athletes);
        expect(over.athleteIds, ['ari', 'andi']);
        expect(over.canResume, true);
        expect(over.resuming().current, 1);
        expect(
          over.withPass(going.pass).phase,
          GuidedPhase.athletes,
          reason: 'changes of the old pass do not take it back',
        );

        final action = over
            .beginActions(passId: 'nueva', now: _t0, redo: true)
            .single;
        expect(action.replaces, going.pass!.id);
        final begun = over.applying([action]);
        expect(begun.phase, GuidedPhase.blocks);
        expect(begun.current, 0);
        expect(begun.redo, true);
      },
    );

    test('the actions carry the pass and the version read', () {
      final g = _onBlock(1);
      final start = g.startBlockActions(_none, now: _at(1)).single;
      expect(start.kind, GuidedActionKind.startBlock);
      expect(start.passId, g.pass!.id);
      expect(start.version, g.pass!.version);
      expect(start.blockIndex, 1);
      expect(start.at, _at(1));
    });

    test(
      'a step finished goes through the pass, so the other device skips it too',
      () {
        final g = _onBlock(1).startBlock(_none, now: _t0);
        final result = g.finishStepActions(_none, now: _t0);
        final other = GuidedSession.following(
          _day,
          g.pass!,
        ).applying(result.actions);

        expect(other.currentStep(_none), _step(0, 0, ['andi']));
      },
    );

    test('the draft goes when the block on screen changes', () {
      final g = _onBlock(1)
          .startBlock(_none, now: _t0)
          .toggleNotDone('ari', _none);
      expect(g.draft, isNotNull);
      expect(g.interruptBlock(now: _t0).draft, isNull);
    });
  });

  group('going back (Ari, 2026-11-21)', () {
    /// Block 1 by turns, running, after Ari's and Andi's first sets: Ari's second is on screen.
    (GuidedSession, Set<BlockSet>) afterTwo() {
      var g = _onBlock(1).startBlock(_none, now: _t0);
      final recorded = <BlockSet>{};
      for (var i = 0; i < 2; i++) {
        final step = g.currentStep(recorded)!;
        final r = g.finishStep(recorded, now: _t0);
        for (final a in r.record) {
          recorded.add((1, AthleteSet(a, step.prescription, step.set)));
        }
        g = r.next;
      }
      return (g, recorded);
    }

    test('behind are the steps already done before the one on screen, in order', () {
      final (g, recorded) = afterTwo();
      expect(g.currentStep(recorded), _step(0, 1, ['ari']));
      expect(g.behind(recorded), [
        _step(0, 0, ['ari']),
        _step(0, 0, ['andi']),
      ]);
      expect(_onBlock(1).startBlock(_none, now: _t0).canGoBack(_none), false);
    });

    test('goes back one step at a time, and not past the first', () {
      final (g, recorded) = afterTwo();
      final once = g.goBack(recorded);
      expect(once.shownStep(recorded), _step(0, 0, ['andi']));
      expect(once.stepAfter(recorded), _step(0, 1, ['ari']));
      final twice = once.goBack(recorded);
      expect(twice.shownStep(recorded), _step(0, 0, ['ari']));
      expect(twice.canGoBack(recorded), false);
      expect(twice.goBack(recorded).shownStep(recorded), _step(0, 0, ['ari']));
      expect(twice.toCurrent().shownStep(recorded), _step(0, 1, ['ari']));
    });

    test('the pass does not move and the draft of the current step stays', () {
      final (g, recorded) = afterTwo();
      final typed = g.edit('ari', const SetEdit(manualKg: 90), recorded);
      final back = typed.goBack(recorded);
      expect(identical(back.pass, typed.pass), true);
      final edited = back.edit('andi', const SetEdit(reps: 3), recorded);
      expect(edited.draftFor(_step(0, 0, ['andi'])).edits['andi']?.reps, 3);
      final current = edited.toCurrent();
      expect(current.draftFor(_step(0, 1, ['ari'])).edits['ari']?.manualKg, 90);
      expect(current.draftFor(_step(0, 1, ['ari'])).edits['andi'], isNull);
    });

    test('finishing a step behind records it again and goes on, without pass actions', () {
      final (g, recorded) = afterTwo();
      final back = g.goBack(recorded).goBack(recorded);
      final r = back.finishReview(recorded);
      expect(r.record, ['ari']);
      expect(identical(r.next.pass, g.pass), true);
      expect(r.next.shownStep(recorded), _step(0, 0, ['andi']));
      final last = r.next.finishReview(recorded);
      expect(last.record, ['andi']);
      expect(last.next.shownStep(recorded), _step(0, 1, ['ari']));
      expect(last.next.reviewing, isNull);
    });

    test('a set passed but not recorded starts as not done', () {
      var g = _onBlock(1)
          .withAthleteMode(AthleteMode.simultaneous)
          .startBlock(_none, now: _t0)
          .toggleNotDone('andi', _none);
      final r = g.finishStep(_none, now: _t0);
      expect(r.record, ['ari']);
      final recorded = {(1, const AthleteSet('ari', 0, 0))};
      g = r.next.goBack(recorded);
      final step = g.shownStep(recorded)!;
      expect(step, _step(0, 0, ['ari', 'andi']));
      expect(g.draftFor(step).notDone, {'andi'});
      expect(g.finishReview(recorded).record, ['ari']);
    });

    test('a step behind is started and finished like any step', () {
      final (g, recorded) = afterTwo();
      final back = g.goBack(recorded);
      final step = back.shownStep(recorded)!;
      expect(back.draftFor(step).running, false);
      final started = back.startStep(recorded);
      expect(started.draftFor(step).running, true);
      expect(
        started.draftFor(started.currentStep(recorded)!).running,
        false,
        reason: 'the step the pass is on is not started by it',
      );
    });

    test('once the block on screen changes, the step behind is dropped', () {
      final (g, recorded) = afterTwo();
      final back = g.goBack(recorded);
      expect(back.interruptBlock(now: _t0).reviewing, isNull);
    });
  });

  group('remembering the position (Ari, 2026-11-21)', () {
    test('restores the drafts and the step behind of the same pass and block', () {
      var g = _onBlock(1).startBlock(_none, now: _t0).startStep(_none);
      g = g.edit('ari', const SetEdit(manualKg: 85, reps: 4), _none);
      final position = g.positionIn('s1')!;
      expect((position.sessionId, position.passId, position.block), ('s1', g.pass!.id, 1));

      final fresh = GuidedSession.following(_day, g.pass!);
      expect(fresh.draft, isNull);
      final back = fresh.restoring(position);
      final draft = back.draftFor(back.currentStep(_none)!);
      expect(draft.running, true);
      expect(draft.edits['ari']?.manualKg, 85);
    });

    test('a position of another pass or block is not taken', () {
      final g = _onBlock(1).startBlock(_none, now: _t0).startStep(_none);
      final position = g.positionIn('s1')!;
      final other = GuidedSession.following(_day, g.interruptBlock(now: _t0).pass!);
      expect(other.restoring(position).draft, isNull);
      final otherPass = GuidedSession.choosing(_day, const ['ari'])
          .begin(now: _t0, passId: 'otra')
          .skipBlock(now: _t0)
          .startBlock(_none, now: _t0);
      expect(otherPass.restoring(position).draft, isNull);
    });

    test('choosing who trains or the summary have no position', () {
      expect(GuidedSession.choosing(_day, const ['ari']).positionIn('s1'), isNull);
    });
  });
}
