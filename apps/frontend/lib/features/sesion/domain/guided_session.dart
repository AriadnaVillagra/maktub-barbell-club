/// The guided mode ("Entrenar", E7.20) as pure state: who trains, which block is on screen, how far each block
/// went and the step being done. Widgets and writes live in `presentation/`.
///
/// See `reference/Guia.html` and decision D19 in docs/work/M1-mvp/design.md. The position is local to the device;
/// what is done comes from the session's records, so a set another device marks drops out of the steps.
library;

import 'package:maktub_core/maktub_core.dart';

/// A set recorded as done: the block it belongs to and the athlete's set in it.
typedef BlockSet = (int block, AthleteSet set);

/// The sets of [records] that are done.
Set<BlockSet> recordedSets(Iterable<SetRecord> records) => {
  for (final r in records)
    if (r.done)
      (r.blockIndex, AthleteSet(r.athleteId, r.prescriptionIndex, r.setIndex)),
};

/// The sets of [recorded] that belong to [athleteIds]: what makes "Comenzar" ask (E7.23).
Set<BlockSet> recordedOfAthletes(
  Set<BlockSet> recorded,
  Iterable<String> athleteIds,
) => {
  for (final r in recorded)
    if (athleteIds.contains(r.$2.athleteId)) r,
};

/// Whether [block] is done set by set. A timed block, or one without sets (a stretch, a WoD), is done as a whole.
bool blockHasSteps(PlanBlock block) =>
    block.executionMode != ExecutionMode.timed &&
    block.prescriptions.any((p) => p.sets.isNotEmpty);

/// How many sets each of [athleteIds] has in each prescription of [block], as `guidedSteps` takes them. Every athlete
/// has the plan's sets today; an athlete with 0 does not have that prescription in their day.
List<Map<String, int>> setCountsOf(PlanBlock block, List<String> athleteIds) =>
    [
      for (final p in block.prescriptions) {
        for (final a in athleteIds) a: p.sets.length,
      },
    ];

enum GuidedPhase {
  /// Choosing who trains.
  athletes,

  /// Going through the blocks, one at a time.
  blocks,

  /// Every block was closed.
  finished,
}

enum GuidedBlockStatus {
  /// Not started yet: its preview is on screen, or it is still ahead.
  pending,
  running,
  done,
  interrupted,
  skipped,
}

/// How far one block of the day went in the guided mode. What E7.21 turns into a `BlockTime` and the summary.
class GuidedBlockRun {
  const GuidedBlockRun({
    required this.blockIndex,
    required this.athleteMode,
    required this.executionMode,
    this.status = GuidedBlockStatus.pending,
    this.start,
    this.end,
    this.left = const {},
    this.passed = const {},
  });

  /// Position of the block in the day (0-based).
  final int blockIndex;

  /// The athlete mode in force; once closed, the one it ended with. Meaningless for a block without steps.
  final AthleteMode athleteMode;

  /// Sequential or circuit in force (E7.22); starts as the plan's and does not change the plan.
  final ExecutionMode executionMode;
  final GuidedBlockStatus status;

  /// When "Iniciar bloque" was tapped and when the block closed; null for a skipped block.
  final DateTime? start;
  final DateTime? end;

  /// Athletes who left a prescription, or the whole prescription when "Saltar este ejercicio".
  final Set<LeftPrescription> left;

  /// Sets this device closed, recorded or marked "No hizo esta serie": they are not offered again.
  final Set<AthleteSet> passed;

  bool get closed =>
      status == GuidedBlockStatus.done ||
      status == GuidedBlockStatus.interrupted ||
      status == GuidedBlockStatus.skipped;

  GuidedBlockRun _copy({
    AthleteMode? athleteMode,
    ExecutionMode? executionMode,
    GuidedBlockStatus? status,
    DateTime? start,
    DateTime? end,
    Set<LeftPrescription>? left,
    Set<AthleteSet>? passed,
  }) => GuidedBlockRun(
    blockIndex: blockIndex,
    athleteMode: athleteMode ?? this.athleteMode,
    executionMode: executionMode ?? this.executionMode,
    status: status ?? this.status,
    start: start ?? this.start,
    end: end ?? this.end,
    left: left ?? this.left,
    passed: passed ?? this.passed,
  );
}

/// Kilos and reps typed on an athlete's card before "Terminar serie". A null [manualKg] lets the server compute
/// them; a null [reps] takes the plan's.
class SetEdit {
  const SetEdit({this.manualKg, this.reps});

  final double? manualKg;
  final int? reps;
}

/// What the step on screen holds before it is finished: whether it was started, who will not do this set and what
/// was typed. Tied to a prescription and set, so it survives the step losing an athlete.
class GuidedStepDraft {
  const GuidedStepDraft({
    required this.prescription,
    required this.set,
    this.running = false,
    this.notDone = const {},
    this.edits = const {},
  });

  final int prescription;
  final int set;

  /// "Iniciar serie" was tapped.
  final bool running;

  /// Athletes marked "No hizo esta serie".
  final Set<String> notDone;
  final Map<String, SetEdit> edits;

  bool isFor(GuidedStep step) =>
      step.prescription == prescription && step.set == set;

  GuidedStepDraft _copy({
    bool? running,
    Set<String>? notDone,
    Map<String, SetEdit>? edits,
  }) => GuidedStepDraft(
    prescription: prescription,
    set: set,
    running: running ?? this.running,
    notDone: notDone ?? this.notDone,
    edits: edits ?? this.edits,
  );
}

/// The guided mode of one day. Immutable: every action returns the next state.
///
/// What is done is never stored here: each call that needs it takes [recorded], the done sets of the session. So the
/// steps are always what is left (D19), unless the day is redone, and the guided mode never unmarks anything.
class GuidedSession {
  const GuidedSession._({
    required this.day,
    required this.phase,
    required this.athleteIds,
    this.redo = false,
    this.runs = const [],
    this.current = 0,
    this.start,
    this.end,
    this.draft,
  });

  /// Starts choosing who trains, with [athleteIds] already chosen.
  factory GuidedSession.choosing(PlanDay day, Iterable<String> athleteIds) =>
      GuidedSession._(
        day: day,
        phase: GuidedPhase.athletes,
        athleteIds: List.unmodifiable(athleteIds),
      );

  final PlanDay day;
  final GuidedPhase phase;

  /// "Hacer todo de nuevo" (E7.23): every set of the chosen athletes is walked again, recorded or not; only what this
  /// run passed counts as done, and finishing a set overwrites its record. Nothing is ever unmarked.
  final bool redo;

  /// Who trains, in the order chosen: the order of the turns and of the cards.
  final List<String> athleteIds;

  /// One per block of the day, in order. Filled when the guided mode begins.
  final List<GuidedBlockRun> runs;

  /// Index of the block on screen.
  final int current;

  /// When the first block started, and when the last one closed.
  final DateTime? start;
  final DateTime? end;
  final GuidedStepDraft? draft;

  GuidedSession _copy({
    GuidedPhase? phase,
    List<String>? athleteIds,
    bool? redo,
    List<GuidedBlockRun>? runs,
    int? current,
    DateTime? start,
    DateTime? end,
    GuidedStepDraft? draft,
    bool clearDraft = false,
  }) => GuidedSession._(
    day: day,
    phase: phase ?? this.phase,
    athleteIds: athleteIds ?? this.athleteIds,
    redo: redo ?? this.redo,
    runs: runs ?? this.runs,
    current: current ?? this.current,
    start: start ?? this.start,
    end: end ?? this.end,
    draft: clearDraft ? null : draft ?? this.draft,
  );

  /// The block on screen and how it goes; null outside [GuidedPhase.blocks].
  GuidedBlockRun? get run => phase == GuidedPhase.blocks ? runs[current] : null;
  PlanBlock? get block => switch (run) {
    final run? => day.blocks[run.blockIndex],
    null => null,
  };

  /// Whether the block on screen offers simultaneous or by turns.
  bool get offersAthleteMode =>
      athleteIds.length > 1 && (block != null && blockHasSteps(block!));

  /// Whether the block on screen offers sequential or circuit: it has sets in more than one prescription.
  bool get offersExecutionMode =>
      block != null &&
      blockHasSteps(block!) &&
      block!.prescriptions.where((p) => p.sets.isNotEmpty).length > 1;

  /// From the first block's start to now, or to the end.
  Duration? elapsed(DateTime now) =>
      start == null ? null : (end ?? now).difference(start!);

  /// What is left of the block on screen, in order: its first one is the step on screen.
  List<GuidedStep> pending(Set<BlockSet> recorded) {
    final run = this.run;
    final block = this.block;
    if (run == null || block == null || !blockHasSteps(block)) return const [];
    return pendingSteps(
      guidedSteps(
        executionMode: run.executionMode,
        athleteMode: run.athleteMode,
        athleteIds: athleteIds,
        setCounts: setCountsOf(block, athleteIds),
      ),
      done: {
        ...run.passed,
        if (!redo)
          for (final (b, s) in recorded)
            if (b == run.blockIndex) s,
      },
      left: run.left,
    );
  }

  /// The step on screen, while a block with steps runs.
  GuidedStep? currentStep(Set<BlockSet> recorded) =>
      run?.status == GuidedBlockStatus.running
      ? pending(recorded).firstOrNull
      : null;

  /// The draft of [step]: empty if what is held belongs to another step.
  GuidedStepDraft draftFor(GuidedStep step) =>
      draft != null && draft!.isFor(step)
      ? draft!
      : GuidedStepDraft(prescription: step.prescription, set: step.set);

  // ---------- athletes ----------

  GuidedSession toggleAthlete(String athleteId) {
    if (phase != GuidedPhase.athletes) return this;
    return _copy(
      athleteIds: athleteIds.contains(athleteId)
          ? [
              for (final a in athleteIds)
                if (a != athleteId) a,
            ]
          : [...athleteIds, athleteId],
    );
  }

  /// "Comenzar": the first block's preview, or straight to the end on a day without blocks.
  ///
  /// With [redo] the day is walked again from the start, whatever is recorded.
  GuidedSession begin({required DateTime now, bool redo = false}) {
    if (phase != GuidedPhase.athletes || athleteIds.isEmpty) return this;
    final runs = [
      for (var b = 0; b < day.blocks.length; b++)
        GuidedBlockRun(
          blockIndex: b,
          athleteMode: day.blocks[b].athleteMode,
          executionMode: day.blocks[b].executionMode,
        ),
    ];
    if (runs.isEmpty) {
      return _copy(
        phase: GuidedPhase.finished,
        runs: runs,
        end: now,
        redo: redo,
      );
    }
    return _copy(
      phase: GuidedPhase.blocks,
      runs: runs,
      current: 0,
      redo: redo,
    );
  }

  // ---------- blocks ----------

  /// Simultaneous or by turns, in the preview or in the middle of the block: only what is left is regrouped.
  GuidedSession withAthleteMode(AthleteMode mode) {
    final run = this.run;
    if (run == null || run.closed) return this;
    return _withRun(run._copy(athleteMode: mode));
  }

  /// Sequential or circuit, in the preview or in the middle of the block: only what is left is reordered (E7.22).
  GuidedSession withExecutionMode(ExecutionMode mode) {
    final run = this.run;
    if (run == null ||
        run.closed ||
        !offersExecutionMode ||
        (mode != ExecutionMode.sequential && mode != ExecutionMode.circuit)) {
      return this;
    }
    return _withRun(run._copy(executionMode: mode));
  }

  /// "Iniciar bloque". A block whose sets are all recorded already closes as done.
  GuidedSession startBlock(Set<BlockSet> recorded, {required DateTime now}) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.pending) return this;
    return _withRun(
      run._copy(status: GuidedBlockStatus.running, start: now),
    )._copy(start: start ?? now).settle(recorded, now: now);
  }

  GuidedSession skipBlock({required DateTime now}) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.pending) return this;
    return _withRun(run._copy(status: GuidedBlockStatus.skipped))._next(now);
  }

  /// "Terminar bloque" of a block without steps.
  GuidedSession finishBlock({required DateTime now}) =>
      _close(GuidedBlockStatus.done, now);

  /// "Interrumpir bloque": what was finished stays, the rest is left undone.
  GuidedSession interruptBlock({required DateTime now}) =>
      _close(GuidedBlockStatus.interrupted, now);

  /// Closes the block on screen as done once nothing is left of it, for example after another device marked its
  /// last sets.
  GuidedSession settle(Set<BlockSet> recorded, {required DateTime now}) {
    final block = this.block;
    if (run?.status != GuidedBlockStatus.running ||
        block == null ||
        !blockHasSteps(block) ||
        pending(recorded).isNotEmpty) {
      return this;
    }
    return _close(GuidedBlockStatus.done, now);
  }

  // ---------- steps ----------

  /// "Iniciar serie" or "Iniciar turno".
  GuidedSession startStep(Set<BlockSet> recorded) =>
      _withDraft(recorded, (d) => d._copy(running: true));

  /// "No hizo esta serie", or back to counting it.
  GuidedSession toggleNotDone(String athleteId, Set<BlockSet> recorded) =>
      _withDraft(
        recorded,
        (d) => d._copy(
          notDone: d.notDone.contains(athleteId)
              ? ({...d.notDone}..remove(athleteId))
              : {...d.notDone, athleteId},
        ),
      );

  GuidedSession edit(String athleteId, SetEdit edit, Set<BlockSet> recorded) =>
      _withDraft(
        recorded,
        (d) => d._copy(edits: {...d.edits, athleteId: edit}),
      );

  /// "Terminar serie" or "Terminar turno": the step is left behind, and [record] are the athletes whose set has to be
  /// written (everyone in it but those marked "No hizo esta serie").
  ({GuidedSession next, List<String> record}) finishStep(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final run = this.run;
    final step = currentStep(recorded);
    if (run == null || step == null) return (next: this, record: const []);
    final draft = draftFor(step);
    final next = _withRun(
      run._copy(
        passed: {
          ...run.passed,
          for (final a in step.athleteIds)
            AthleteSet(a, step.prescription, step.set),
        },
      ),
    )._copy(clearDraft: true).settle(recorded, now: now);
    return (
      next: next,
      record: [
        for (final a in step.athleteIds)
          if (!draft.notDone.contains(a)) a,
      ],
    );
  }

  /// "Dejar el ejercicio": [athleteId] does none of the sets they have left of the step's prescription.
  GuidedSession leaveExercise(
    String athleteId,
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final run = this.run;
    final step = currentStep(recorded);
    if (run == null || step == null) return this;
    return _withRun(
      run._copy(
        left: {...run.left, LeftPrescription(athleteId, step.prescription)},
      ),
    ).settle(recorded, now: now);
  }

  /// "Saltar este ejercicio": nobody does what is left of the step's prescription.
  GuidedSession skipExercise(Set<BlockSet> recorded, {required DateTime now}) {
    final run = this.run;
    final step = currentStep(recorded);
    if (run == null || step == null) return this;
    return _withRun(
      run._copy(
        left: {
          ...run.left,
          for (final a in athleteIds) LeftPrescription(a, step.prescription),
        },
      ),
    )._copy(clearDraft: true).settle(recorded, now: now);
  }

  // ---------- internals ----------

  GuidedSession _withRun(GuidedBlockRun run) =>
      _copy(runs: [...runs]..[current] = run);

  GuidedSession _withDraft(
    Set<BlockSet> recorded,
    GuidedStepDraft Function(GuidedStepDraft) change,
  ) {
    final step = currentStep(recorded);
    if (step == null) return this;
    return _copy(draft: change(draftFor(step)));
  }

  GuidedSession _close(GuidedBlockStatus status, DateTime now) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.running) return this;
    return _withRun(run._copy(status: status, end: now))._next(now);
  }

  GuidedSession _next(DateTime now) {
    final next = current + 1;
    if (next >= runs.length) {
      return _copy(phase: GuidedPhase.finished, end: now, clearDraft: true);
    }
    return _copy(current: next, clearDraft: true);
  }
}
