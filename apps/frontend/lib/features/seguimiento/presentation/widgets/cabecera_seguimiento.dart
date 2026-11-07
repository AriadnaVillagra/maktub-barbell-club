import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../controllers/estado_seguimiento.dart';
import '../controllers/seguimiento_controller.dart';

/// Selectores de atleta, semana, día y fecha.
class CabeceraSeguimiento extends ConsumerWidget {
  const CabeceraSeguimiento({super.key, required this.estado});

  final SeguimientoListo estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.read(seguimientoControllerProvider.notifier);
    final e = estado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        SegmentedButton<String>(
          segments: [for (final a in e.datos.atletas) ButtonSegment(value: a.id, label: Text(a.nombre))],
          selected: {e.atletaId},
          onSelectionChanged: (s) => control.elegirAtleta(s.single),
        ),
        _Fila(
          etiqueta: 'Semana',
          children: [
            for (final s in [1, 2, 3, 4])
              ChoiceChip(
                selected: s == e.semana,
                avatar: e.semanaCompleta(s) ? const Icon(Icons.check, size: 16) : null,
                label: Text('S$s · ${e.varianteDe(s).etiqueta}'),
                onSelected: (_) => control.elegirSemana(s),
              ),
          ],
        ),
        _Fila(
          etiqueta: 'Día',
          children: [
            for (final d in e.plan.numerosDeDia)
              ChoiceChip(
                selected: d == e.dia,
                avatar: e.diaRegistrado(e.semana, d) ? const Icon(Icons.check, size: 16) : null,
                label: Text('Día $d'),
                onSelected: (_) => control.elegirDia(d),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 16),
              label: Text(aIsoFecha(e.fecha)),
              onPressed: () async {
                final elegida = await showDatePicker(
                  context: context,
                  initialDate: e.fecha,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (elegida != null) control.cambiarFecha(elegida);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.etiqueta, required this.children});

  final String etiqueta;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(etiqueta, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: children)),
        ],
      );
}
