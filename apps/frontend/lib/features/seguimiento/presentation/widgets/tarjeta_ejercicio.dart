import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../temporizador/presentation/controllers/crono_controller.dart';
import '../../../temporizador/presentation/widgets/selector_temporizador.dart';
import '../../domain/entities/sesion_del_dia.dart';
import '../controllers/seguimiento_controller.dart';
import '../providers.dart';
import 'campo_numero.dart';
import 'control_ajuste.dart';
import 'formato.dart';

class TarjetaEjercicio extends ConsumerStatefulWidget {
  const TarjetaEjercicio({
    super.key,
    required this.indice,
    required this.item,
    required this.ajusteSesion,
    required this.temporizadores,
  });

  final int indice;
  final ItemCargado item;
  final int ajusteSesion;
  final Map<String, Temporizador> temporizadores;

  @override
  ConsumerState<TarjetaEjercicio> createState() => _TarjetaEjercicioState();
}

class _TarjetaEjercicioState extends ConsumerState<TarjetaEjercicio> {
  var _abierta = false;

  SeguimientoController get _control => ref.read(seguimientoControllerProvider.notifier);

  Temporizador? get _temporizador => widget.temporizadores[widget.item.temporizadorId];

  Future<void> _arrancarCrono() async {
    final t = _temporizador ?? await elegirTemporizador(context, widget.temporizadores.values);
    if (t == null || !mounted) return;
    if (!ref.read(cronoControllerProvider.notifier).iniciar(t)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ese temporizador no tiene duración cargada.')));
    }
  }

  void _marcar(int serie, bool estabaHecha) {
    _control.alternarHecha(widget.indice, serie);
    final t = _temporizador;
    if (!estabaHecha && t != null) ref.read(cronoControllerProvider.notifier).iniciar(t);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final equipo = ref.watch(equipoProvider);
    final series = it.vista(widget.ajusteSesion, equipo);
    final editado = it.editado(widget.ajusteSesion, equipo);
    final meta = metaDeItem(it, widget.ajusteSesion);
    final tema = Theme.of(context);

    return Card(
      shape: editado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: tema.colorScheme.tertiary),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _abierta = !_abierta),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.ejercicio.nombre, style: tema.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          meta.texto,
                          style: tema.textTheme.bodySmall?.copyWith(color: meta.alerta ? tema.colorScheme.error : null),
                        ),
                        const SizedBox(height: 4),
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.timer_outlined, size: 18),
                          label: Text(_temporizador?.nombre ?? 'elegir'),
                          onPressed: _arrancarCrono,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      resumenDeSeries(series),
                      textAlign: TextAlign.end,
                      style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_abierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  for (final (j, s) in series.indexed)
                    Row(
                      spacing: 8,
                      children: [
                        SizedBox(
                          width: 96,
                          child: s.hecha
                              ? FilledButton(onPressed: () => _marcar(j, true), child: Text('✓ ${s.serie}'))
                              : OutlinedButton(onPressed: () => _marcar(j, false), child: Text('Serie ${s.serie}')),
                        ),
                        Expanded(
                          child: CampoNumero(
                            valor: s.pesoKg,
                            sufijo: 'kg',
                            onCambio: (v) => _control.editarPeso(widget.indice, j, v?.toDouble()),
                          ),
                        ),
                        Expanded(
                          child: CampoNumero(
                            valor: s.reps,
                            sufijo: 'reps',
                            decimales: false,
                            onCambio: (v) => _control.editarReps(widget.indice, j, v?.toInt()),
                          ),
                        ),
                      ],
                    ),
                  if (it.cargaPorRm)
                    ControlAjuste(
                      titulo: 'Ajuste de este ejercicio',
                      valor: it.ajusteEfectivo(widget.ajusteSesion),
                      propio: it.ajuste != null,
                      onCambio: (d) => _control.cambiarAjusteItem(widget.indice, d),
                    ),
                  TextFormField(
                    initialValue: it.nota,
                    decoration: const InputDecoration(hintText: 'Nota (opcional)', isDense: true),
                    onChanged: (v) => _control.editarNota(widget.indice, v),
                  ),
                  if (editado)
                    TextButton.icon(
                      onPressed: () => _control.restaurar(widget.indice),
                      icon: const Icon(Icons.undo),
                      label: const Text('Volver a lo planificado'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
