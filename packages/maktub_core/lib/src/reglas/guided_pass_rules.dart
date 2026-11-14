/// How a write of the guided pass changes it (E7.26). Pure, shared by the server, which applies every write over the
/// state it has, and by the devices, which show their writes before the server answers.
library;

import '../modelos/guided_pass.dart';
import '../modelos/plan.dart';

/// [pass] after [action]. Returns [pass] itself (identical) when the action no longer makes sense over it: for a
/// pass other than the current one, a block that is not where the action expects it, or something already done.
/// So applying an action twice, or after a newer change of another device, is harmless. Each change raises the
/// version by one.
GuidedPass? applyGuidedAction(GuidedPass? pass, GuidedPassAction action) {
  if (action.kind == GuidedActionKind.begin) return _begin(pass, action);
  if (pass == null || pass.id != action.passId || pass.finished) return pass;
  final b = action.blockIndex;
  final run = b != null && b < pass.blocks.length ? pass.blocks[b] : null;
  GuidedPass withRun(GuidedBlockRun next) =>
      _changed(pass, blocks: [...pass.blocks]..[b!] = next);

  switch (action.kind) {
    case GuidedActionKind.begin:
      return pass; // handled above
    case GuidedActionKind.athleteMode:
      final mode = action.athleteMode;
      if (run == null ||
          run.closed ||
          mode == null ||
          run.athleteMode == mode) {
        return pass;
      }
      return withRun(run.copyWith(athleteMode: mode));
    case GuidedActionKind.executionMode:
      final mode = action.executionMode;
      if (run == null ||
          run.closed ||
          (mode != ExecutionMode.sequential && mode != ExecutionMode.circuit) ||
          run.executionMode == ExecutionMode.timed ||
          run.executionMode == mode) {
        return pass;
      }
      return withRun(run.copyWith(executionMode: mode));
    case GuidedActionKind.startBlock:
      if (run == null ||
          b != pass.current ||
          run.status != GuidedBlockStatus.pending) {
        return pass;
      }
      final started = withRun(
        run.copyWith(status: GuidedBlockStatus.running, start: action.at),
      );
      return pass.start == null ? started.copyWith(start: action.at) : started;
    case GuidedActionKind.skipBlock:
      if (run == null ||
          b != pass.current ||
          run.status != GuidedBlockStatus.pending) {
        return pass;
      }
      return _advance(
        withRun(run.copyWith(status: GuidedBlockStatus.skipped)),
        action.at,
      );
    case GuidedActionKind.finishBlock || GuidedActionKind.interruptBlock:
      if (run == null || run.status != GuidedBlockStatus.running) return pass;
      final closed = withRun(
        run.copyWith(
          status: action.kind == GuidedActionKind.finishBlock
              ? GuidedBlockStatus.done
              : GuidedBlockStatus.interrupted,
          end: action.at,
        ),
      );
      return b == pass.current ? _advance(closed, action.at) : closed;
    case GuidedActionKind.passSets:
      if (run == null ||
          run.status != GuidedBlockStatus.running ||
          run.passed.containsAll(action.sets)) {
        return pass;
      }
      return withRun(run.copyWith(passed: {...run.passed, ...action.sets}));
    case GuidedActionKind.leave:
      if (run == null ||
          run.status != GuidedBlockStatus.running ||
          run.left.containsAll(action.left)) {
        return pass;
      }
      return withRun(run.copyWith(left: {...run.left, ...action.left}));
    case GuidedActionKind.finish:
      // A block still running closes as interrupted: what was finished stays.
      final blocks = [
        for (final r in pass.blocks)
          r.status == GuidedBlockStatus.running
              ? r.copyWith(
                  status: GuidedBlockStatus.interrupted,
                  end: action.at,
                )
              : r,
      ];
      return _changed(pass, blocks: blocks, finished: true, end: action.at);
  }
}

/// A new pass, unless another one that is still going on was begun after the one the device saw (it joins that one),
/// or this same pass is already there.
GuidedPass? _begin(GuidedPass? pass, GuidedPassAction action) {
  if (pass != null) {
    if (pass.id == action.passId) return pass;
    if (!pass.finished && pass.id != action.replaces) return pass;
  }
  if (action.athleteIds.isEmpty) return pass;
  final blocks = [
    for (var b = 0; b < action.blockStarts.length; b++)
      GuidedBlockRun(
        blockIndex: b,
        athleteMode: action.blockStarts[b].athleteMode,
        executionMode: action.blockStarts[b].executionMode,
      ),
  ];
  return GuidedPass(
    id: action.passId,
    version: (pass?.version ?? 0) + 1,
    athleteIds: List.unmodifiable(action.athleteIds),
    redo: action.redo,
    blocks: blocks,
    // A day without blocks has nothing to walk.
    finished: blocks.isEmpty,
    end: blocks.isEmpty ? action.at : null,
  );
}

GuidedPass _changed(
  GuidedPass pass, {
  List<GuidedBlockRun>? blocks,
  int? current,
  bool? finished,
  DateTime? end,
}) => pass.copyWith(
  version: pass.version + 1,
  blocks: blocks,
  current: current,
  finished: finished,
  end: end,
);

/// The next block's preview, or the end after the last one. [pass] already counts the change that closed the block.
GuidedPass _advance(GuidedPass pass, DateTime at) {
  final next = pass.current + 1;
  return next >= pass.blocks.length
      ? pass.copyWith(finished: true, end: at)
      : pass.copyWith(current: next);
}
