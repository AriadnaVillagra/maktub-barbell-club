import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart'
    show clubTimersProvider;
import '../../temporizador/presentation/controllers/crono_controller.dart';
import '../../temporizador/presentation/widgets/selector_temporizador.dart';

/// The timer a set starts when it is marked: the prescription's own, or else the block's default rest timer. A timed
/// block's timer, and a `wod` block's, is the block's own (the WoD), not a rest, so marking a set does not start it.
Temporizador? timerForSet(
  PlanBlock block,
  Prescription prescription,
  Iterable<Temporizador> timers,
) {
  final id =
      prescription.timerId ??
      (block.executionMode == ExecutionMode.timed ||
              block.categoryId == wodCategoryId
          ? null
          : block.timerId);
  if (id == null) return null;
  for (final t in timers) {
    if (t.id == id) return t;
  }
  return null;
}

/// What the session screen does with timers: the club's timers, loaded once, and the way to start one.
class SessionTimers {
  SessionTimers._(this._ref, this.all);

  /// Watches the club's timers, so a widget that marks sets has them loaded and rebuilds when they arrive.
  factory SessionTimers.watch(WidgetRef ref) =>
      SessionTimers._(ref, ref.watch(clubTimersProvider).value ?? const []);

  final WidgetRef _ref;

  /// Both states: an archived timer still resolves where a plan already uses it.
  final List<Temporizador> all;

  /// What starts the timer of a set, or null if its prescription has none. Resolve it before awaiting the write that
  /// marks the set, so nothing reads the widget's `ref` after it may be gone.
  VoidCallback? starterFor(PlanBlock block, Prescription prescription) {
    final timer = timerForSet(block, prescription, all);
    if (timer == null) return null;
    final crono = _ref.read(cronoControllerProvider.notifier);
    return () => crono.iniciar(timer);
  }
}

/// Opens the timer picker and starts what the user chooses, for a rest or a WoD the plan does not tie to a set.
class SessionTimerButton extends ConsumerWidget {
  const SessionTimerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    return IconButton(
      key: const Key('session-timer-pick'),
      tooltip: 'Temporizador',
      icon: const Icon(Icons.timer_outlined),
      onPressed: () async {
        final crono = ref.read(cronoControllerProvider.notifier);
        final chosen = await elegirTemporizador(context, [
          for (final t in timers)
            if (t.estado == CatalogStatus.active) t,
        ]);
        if (chosen != null) crono.iniciar(chosen);
      },
    );
  }
}

/// The button of a `wod` block that starts the block's own timer. Nothing if the block has no timer, or the club's
/// timers do not have it.
class SessionWodTimerButton extends ConsumerWidget {
  const SessionWodTimerButton({super.key, required this.block});

  final PlanBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = block.timerId;
    if (id == null) return const SizedBox.shrink();
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    for (final t in timers) {
      if (t.id == id) {
        return OutlinedButton(
          key: const Key('session-wod-timer'),
          onPressed: () =>
              ref.read(cronoControllerProvider.notifier).iniciar(t),
          child: Text('⏱ ${t.nombre}'),
        );
      }
    }
    return const SizedBox.shrink();
  }
}
