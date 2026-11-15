/// The guided mode ("Entrenar", E7.20) as pure state: who trains, which block is on screen, how far each block
/// went and the step being done. Widgets and writes live in `presentation/`.
///
/// See `reference/Guia.html` and decision D19 in docs/work/M1-mvp/design.md. Since E7.26 the position is the
/// session's guided pass ([GuidedPass]), the same on every device: each action here is a [GuidedPassAction] that the
/// device applies at once and queues for the server. What is done comes from the session's records and the sets the
/// pass went through, so a set another device finishes drops out of the steps. Only the athletes being chosen and the
/// draft of the step on screen stay on the device.
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
      for (final p in block.prescriptions)
        {for (final a in athleteIds) a: p.sets.length},
    ];

enum GuidedPhase {
  /// Choosing who trains.
  athletes,

  /// Going through the blocks, one at a time.
  blocks,

  /// The pass finished.
  finished,
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

/// The guided mode of one day over the session's guided pass. Immutable: what stays on the device (who is being
/// chosen, the step's draft) returns the next state; what changes the pass is a list of [GuidedPassAction]s, which the
/// device applies at once with [applying] and queues for the server.
///
/// What is done is never stored here: each call that needs it takes [recorded], the done sets of the session. So the
/// steps are always what is left (D19), unless the day is redone, and the guided mode never unmarks anything.
class GuidedSession {
  const GuidedSession._({
    required this.day,
    this.pass,
    this.choosing = false,
    this.chosen = const [],
    this.replacing,
    this.draft,
  });

  /// Choosing who trains, with [athleteIds] already chosen. [pass] is the session's pass, if any: the new one replaces
  /// it.
  factory GuidedSession.choosing(
    PlanDay day,
    Iterable<String> athleteIds, {
    GuidedPass? pass,
  }) => GuidedSession._(
    day: day,
    pass: pass,
    choosing: true,
    chosen: List.unmodifiable(athleteIds),
    replacing: pass?.id,
  );

  /// Following [pass], wherever it is.
  factory GuidedSession.following(PlanDay day, GuidedPass pass) =>
      GuidedSession._(day: day, pass: pass);

  /// Entering the guided mode (E7.26): a pass going on is resumed without asking anything; otherwise it starts
  /// choosing who trains, with [athleteIds].
  factory GuidedSession.entering(
    PlanDay day,
    GuidedPass? pass,
    Iterable<String> athleteIds,
  ) => pass != null && !pass.finished
      ? GuidedSession.following(day, pass)
      : GuidedSession.choosing(day, athleteIds, pass: pass);

  final PlanDay day;

  /// The session's pass as this device knows it: the server's, with what this device has not sent yet applied.
  final GuidedPass? pass;

  /// Whether who trains is being chosen, for a first pass or for a new one.
  final bool choosing;

  /// Who is chosen so far, while [choosing].
  final List<String> chosen;

  /// The pass the device saw when it started choosing: a new one replaces it, while one begun meanwhile by another
  /// device is joined.
  final String? replacing;
  final GuidedStepDraft? draft;

  GuidedSession _copy({
    GuidedPass? pass,
    bool? choosing,
    List<String>? chosen,
    GuidedStepDraft? draft,
    bool clearDraft = false,
  }) => GuidedSession._(
    day: day,
    pass: pass ?? this.pass,
    choosing: choosing ?? this.choosing,
    chosen: chosen ?? this.chosen,
    replacing: replacing,
    draft: clearDraft ? null : draft ?? this.draft,
  );

  GuidedPhase get phase => choosing || pass == null
      ? GuidedPhase.athletes
      : pass!.finished
      ? GuidedPhase.finished
      : GuidedPhase.blocks;

  /// "Hacer todo de nuevo" (E7.23): every set of the chosen athletes is walked again, recorded or not; only what this
  /// pass went through counts as done, and finishing a set overwrites its record. Nothing is ever unmarked.
  bool get redo => phase != GuidedPhase.athletes && (pass?.redo ?? false);

  /// Who trains, in the order chosen: the order of the turns and of the cards.
  List<String> get athleteIds =>
      phase == GuidedPhase.athletes ? chosen : pass!.athleteIds;

  /// One per block of the day, in order. Filled when the pass begins.
  List<GuidedBlockRun> get runs =>
      phase == GuidedPhase.athletes ? const [] : pass!.blocks;

  /// Index of the block on screen.
  int get current => phase == GuidedPhase.athletes ? 0 : pass!.current;

  /// When the first block started, and when the pass finished.
  DateTime? get start => phase == GuidedPhase.athletes ? null : pass!.start;
  DateTime? get end => phase == GuidedPhase.athletes ? null : pass!.end;

  /// The block on screen and how it goes; null outside [GuidedPhase.blocks] or if the plan no longer has it.
  GuidedBlockRun? get run {
    if (phase != GuidedPhase.blocks) return null;
    final run = pass!.run;
    return run != null && run.blockIndex < day.blocks.length ? run : null;
  }

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

  /// From the first block's start to now, or to the end. The instants are the pass's, so every device shows the same.
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

  /// The same, without the draft of the step on screen.
  GuidedSession clearingDraft() => _copy(clearDraft: true);

  // ---------- the pass ----------

  /// With [pass] as the session has it now. While choosing, a pass other than the one the device saw is followed: the
  /// one "Comenzar" began, or one another device began meanwhile. The draft goes once the block on screen changes.
  GuidedSession withPass(GuidedPass? pass) {
    final joins = choosing && pass != null && pass.id != replacing;
    final moved =
        pass?.id != this.pass?.id ||
        pass?.current != this.pass?.current ||
        pass?.run?.status != this.pass?.run?.status;
    return GuidedSession._(
      day: day,
      pass: pass,
      choosing: choosing && !joins,
      chosen: chosen,
      replacing: replacing,
      draft: moved ? null : draft,
    );
  }

  /// With [actions] applied to the pass, as the server will apply them.
  GuidedSession applying(Iterable<GuidedPassAction> actions) =>
      withPass(actions.fold(pass, applyGuidedAction));

  GuidedPassAction _on(GuidedActionKind kind, int block, DateTime now) =>
      GuidedPassAction.onBlock(
        kind,
        passId: pass!.id,
        version: pass!.version,
        at: now,
        block: block,
      );

  /// [actions] followed by closing the block, if nothing is left of it after them.
  List<GuidedPassAction> _thenSettle(
    List<GuidedPassAction> actions,
    Set<BlockSet> recorded,
    DateTime now,
  ) => [...actions, ...applying(actions).settleActions(recorded, now: now)];

  // ---------- athletes ----------

  GuidedSession toggleAthlete(String athleteId) {
    if (phase != GuidedPhase.athletes) return this;
    return _copy(
      chosen: chosen.contains(athleteId)
          ? [
              for (final a in chosen)
                if (a != athleteId) a,
            ]
          : [...chosen, athleteId],
    );
  }

  /// Back to choosing who trains, for a new pass that replaces this one ("Empezar de nuevo"). Nothing is written until
  /// "Comenzar".
  GuidedSession startingOver() =>
      GuidedSession.choosing(day, pass?.athleteIds ?? chosen, pass: pass);

  /// Whether a pass is going on behind the athletes being chosen, so choosing can be left to go back to it.
  bool get canResume =>
      phase == GuidedPhase.athletes && pass != null && !pass!.finished;

  /// Leaves choosing and goes back to the pass going on.
  GuidedSession resuming() =>
      canResume ? GuidedSession.following(day, pass!) : this;

  /// "Comenzar": a new pass [passId], on the first block's preview, or straight to the end on a day without blocks.
  /// With [redo] the day is walked again from the start, whatever is recorded.
  List<GuidedPassAction> beginActions({
    required String passId,
    required DateTime now,
    bool redo = false,
  }) {
    if (phase != GuidedPhase.athletes || chosen.isEmpty) return const [];
    return [
      GuidedPassAction.begin(
        passId: passId,
        version: pass?.version ?? 0,
        at: now,
        replaces: replacing,
        athleteIds: chosen,
        redo: redo,
        blocks: [
          for (final b in day.blocks)
            GuidedBlockStart(
              athleteMode: b.athleteMode,
              executionMode: b.executionMode,
            ),
        ],
      ),
    ];
  }

  GuidedSession begin({
    required DateTime now,
    bool redo = false,
    String passId = 'pasada',
  }) => applying(beginActions(passId: passId, now: now, redo: redo));

  // ---------- blocks ----------

  /// Simultaneous or by turns, in the preview or in the middle of the block: only what is left is regrouped.
  List<GuidedPassAction> athleteModeActions(
    AthleteMode mode, {
    required DateTime now,
  }) {
    final run = this.run;
    if (run == null || run.closed || run.athleteMode == mode) return const [];
    return [
      GuidedPassAction.athleteMode(
        passId: pass!.id,
        version: pass!.version,
        at: now,
        block: run.blockIndex,
        mode: mode,
      ),
    ];
  }

  GuidedSession withAthleteMode(AthleteMode mode, {DateTime? now}) =>
      applying(athleteModeActions(mode, now: now ?? _epoch));

  /// Sequential or circuit, in the preview or in the middle of the block: only what is left is reordered (E7.22).
  List<GuidedPassAction> executionModeActions(
    ExecutionMode mode, {
    required DateTime now,
  }) {
    final run = this.run;
    if (run == null ||
        run.closed ||
        !offersExecutionMode ||
        run.executionMode == mode ||
        (mode != ExecutionMode.sequential && mode != ExecutionMode.circuit)) {
      return const [];
    }
    return [
      GuidedPassAction.executionMode(
        passId: pass!.id,
        version: pass!.version,
        at: now,
        block: run.blockIndex,
        mode: mode,
      ),
    ];
  }

  GuidedSession withExecutionMode(ExecutionMode mode, {DateTime? now}) =>
      applying(executionModeActions(mode, now: now ?? _epoch));

  /// "Iniciar bloque". A block whose sets are all recorded already closes as done.
  List<GuidedPassAction> startBlockActions(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.pending) return const [];
    return _thenSettle(
      [_on(GuidedActionKind.startBlock, run.blockIndex, now)],
      recorded,
      now,
    );
  }

  GuidedSession startBlock(Set<BlockSet> recorded, {required DateTime now}) =>
      applying(startBlockActions(recorded, now: now));

  List<GuidedPassAction> skipBlockActions({required DateTime now}) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.pending) return const [];
    return [_on(GuidedActionKind.skipBlock, run.blockIndex, now)];
  }

  GuidedSession skipBlock({required DateTime now}) =>
      applying(skipBlockActions(now: now));

  /// "Terminar bloque" of a block without steps.
  List<GuidedPassAction> finishBlockActions({required DateTime now}) =>
      _closing(GuidedActionKind.finishBlock, now);

  GuidedSession finishBlock({required DateTime now}) =>
      applying(finishBlockActions(now: now));

  /// "Interrumpir bloque": what was finished stays, the rest is left undone.
  List<GuidedPassAction> interruptBlockActions({required DateTime now}) =>
      _closing(GuidedActionKind.interruptBlock, now);

  GuidedSession interruptBlock({required DateTime now}) =>
      applying(interruptBlockActions(now: now));

  /// Closes the block on screen as done once nothing is left of it, for example after another device marked its
  /// last sets.
  List<GuidedPassAction> settleActions(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final block = this.block;
    if (run?.status != GuidedBlockStatus.running ||
        block == null ||
        !blockHasSteps(block) ||
        pending(recorded).isNotEmpty) {
      return const [];
    }
    return _closing(GuidedActionKind.finishBlock, now);
  }

  GuidedSession settle(Set<BlockSet> recorded, {required DateTime now}) =>
      applying(settleActions(recorded, now: now));

  /// "Terminar el día": the pass closes for every device, and a block still running is interrupted.
  List<GuidedPassAction> finishDayActions({required DateTime now}) =>
      phase == GuidedPhase.blocks
      ? [
          GuidedPassAction.finish(
            passId: pass!.id,
            version: pass!.version,
            at: now,
          ),
        ]
      : const [];

  GuidedSession finishDay({required DateTime now}) =>
      applying(finishDayActions(now: now));

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

  /// "Terminar serie" or "Terminar turno": the step is left behind ([actions]), and [record] are the athletes whose
  /// set has to be written (everyone in it but those marked "No hizo esta serie").
  ({List<GuidedPassAction> actions, List<String> record}) finishStepActions(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final run = this.run;
    final step = currentStep(recorded);
    if (run == null || step == null) {
      return (actions: const [], record: const []);
    }
    final draft = draftFor(step);
    return (
      actions: _thenSettle(
        [
          GuidedPassAction.passSets(
            passId: pass!.id,
            version: pass!.version,
            at: now,
            block: run.blockIndex,
            sets: {
              for (final a in step.athleteIds)
                AthleteSet(a, step.prescription, step.set),
            },
          ),
        ],
        recorded,
        now,
      ),
      record: [
        for (final a in step.athleteIds)
          if (!draft.notDone.contains(a)) a,
      ],
    );
  }

  ({GuidedSession next, List<String> record}) finishStep(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final result = finishStepActions(recorded, now: now);
    return (
      next: applying(result.actions)._copy(clearDraft: true),
      record: result.record,
    );
  }

  /// "Dejar el ejercicio": [athleteId] does none of the sets they have left of the step's prescription.
  List<GuidedPassAction> leaveExerciseActions(
    String athleteId,
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final step = currentStep(recorded);
    if (step == null) return const [];
    return _leaving(
      {LeftPrescription(athleteId, step.prescription)},
      recorded,
      now,
    );
  }

  GuidedSession leaveExercise(
    String athleteId,
    Set<BlockSet> recorded, {
    required DateTime now,
  }) => applying(leaveExerciseActions(athleteId, recorded, now: now));

  /// "Saltar este ejercicio": nobody does what is left of the step's prescription.
  List<GuidedPassAction> skipExerciseActions(
    Set<BlockSet> recorded, {
    required DateTime now,
  }) {
    final step = currentStep(recorded);
    if (step == null) return const [];
    return _leaving(
      {for (final a in athleteIds) LeftPrescription(a, step.prescription)},
      recorded,
      now,
    );
  }

  GuidedSession skipExercise(Set<BlockSet> recorded, {required DateTime now}) =>
      applying(skipExerciseActions(recorded, now: now))._copy(clearDraft: true);

  // ---------- internals ----------

  static final _epoch = DateTime.utc(1970);

  List<GuidedPassAction> _leaving(
    Set<LeftPrescription> left,
    Set<BlockSet> recorded,
    DateTime now,
  ) => _thenSettle(
    [
      GuidedPassAction.leave(
        passId: pass!.id,
        version: pass!.version,
        at: now,
        block: run!.blockIndex,
        left: left,
      ),
    ],
    recorded,
    now,
  );

  List<GuidedPassAction> _closing(GuidedActionKind kind, DateTime now) {
    final run = this.run;
    if (run == null || run.status != GuidedBlockStatus.running) return const [];
    return [_on(kind, run.blockIndex, now)];
  }

  GuidedSession _withDraft(
    Set<BlockSet> recorded,
    GuidedStepDraft Function(GuidedStepDraft) change,
  ) {
    final step = currentStep(recorded);
    if (step == null) return this;
    return _copy(draft: change(draftFor(step)));
  }
}
