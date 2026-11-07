import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../controllers/crono_controller.dart';

/// Barra fija con el temporizador en marcha. No ocupa lugar si no hay ninguno.
class BarraCrono extends ConsumerWidget {
  const BarraCrono({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(cronoControllerProvider);
    if (vista == null) return const SizedBox.shrink();

    final control = ref.read(cronoControllerProvider.notifier);
    final crono = vista.crono;
    final esquema = Theme.of(context).colorScheme;
    final ultimos = vista.restantes <= 3 && !crono.enPausa;
    final fondo = ultimos
        ? esquema.errorContainer
        : crono.fase.esTrabajo && crono.porRondas
            ? esquema.tertiaryContainer
            : esquema.primaryContainer;

    return Material(
      color: fondo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(crono.temporizador.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    crono.porRondas
                        ? '${crono.fase.etiqueta} · ronda ${crono.fase.ronda}/${crono.fase.rondas}'
                        : crono.fase.etiqueta,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              reloj(vista.restantes),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            if (!crono.porRondas) ...[
              IconButton(tooltip: '−30 s', onPressed: () => control.sumar(-30), icon: const Icon(Icons.replay_30)),
              IconButton(tooltip: '+30 s', onPressed: () => control.sumar(30), icon: const Icon(Icons.forward_30)),
            ],
            IconButton(
              tooltip: crono.enPausa ? 'Seguir' : 'Pausar',
              onPressed: control.alternarPausa,
              icon: Icon(crono.enPausa ? Icons.play_arrow : Icons.pause),
            ),
            IconButton(tooltip: 'Cerrar', onPressed: control.detener, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
