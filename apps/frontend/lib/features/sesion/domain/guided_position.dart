/// Where this device was in the guided mode, so leaving it (another tab, the session's list, a reload of the PWA)
/// and coming back lands on the same step, with what was typed on it (Ari, 2026-11-21).
///
/// The block and the step on screen come from the session's guided pass (E7.26), the same on every device. What is
/// remembered here is only what stays on the device: the draft of the step on screen and the step shown again with
/// "Atrás". It belongs to one session and one pass: for any other it is dropped.
library;

import 'package:maktub_core/maktub_core.dart';

import 'guided_session.dart';

class GuidedPosition {
  const GuidedPosition({
    required this.sessionId,
    required this.passId,
    required this.block,
    this.draft,
    this.reviewing,
    this.reviewDraft,
  });

  final String sessionId;
  final String passId;

  /// The block on screen when it was remembered. Once the pass is on another block, nothing of this applies.
  final int block;

  /// The draft of the step the pass is on.
  final GuidedStepDraft? draft;

  /// The step behind shown again with "Atrás", and its draft.
  final GuidedStep? reviewing;
  final GuidedStepDraft? reviewDraft;
}

/// Where the device keeps the last [GuidedPosition]. One is enough: only one guided mode is open at a time.
abstract interface class GuidedPositionStore {
  /// The saved position; null when there is none or it cannot be read.
  Future<GuidedPosition?> load();

  /// Saves [position], or forgets the saved one with null.
  Future<void> save(GuidedPosition? position);
}

/// The position kept in memory for the whole app's life, over [GuidedPositionStore], which lets it outlive a reload.
/// The guided mode's state goes when its screen goes; this does not.
class RememberedGuidedPosition {
  RememberedGuidedPosition(this._store);

  final GuidedPositionStore _store;
  GuidedPosition? _value;
  var _loaded = false;
  Future<void>? _loading;

  /// Whether [value] can be trusted: loaded from the store, or saved since.
  bool get loaded => _loaded;
  GuidedPosition? get value => _value;

  /// Reads the store once. A position saved meanwhile wins.
  Future<void> load() => _loading ??= () async {
    final saved = await _store.load();
    if (!_loaded) _value = saved;
    _loaded = true;
  }();

  void save(GuidedPosition? position) {
    _value = position;
    _loaded = true;
    _store.save(position).ignore();
  }
}
