import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../temporizador/presentation/controllers/crono_controller.dart';
import '../../../temporizador/presentation/widgets/barra_crono.dart';
import '../../../temporizador/presentation/widgets/selector_temporizador.dart';
import '../../domain/entities/sesion_del_dia.dart';
import '../controllers/estado_seguimiento.dart';
import '../controllers/seguimiento_controller.dart';
import '../widgets/cabecera_seguimiento.dart';
import '../widgets/control_ajuste.dart';
import '../widgets/formato.dart';
import '../widgets/tarjeta_ejercicio.dart';

/// Qué toca hoy, con los kilos ya calculados. Se usa en el gimnasio.
class SeguimientoPage extends ConsumerWidget {
  const SeguimientoPage({super.key});

  void _avisar(BuildContext context, String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _ejecutar(BuildContext context, Future<void> Function() accion, String exito) async {
    try {
      await accion();
      if (context.mounted) _avisar(context, exito);
    } catch (e) {
      if (context.mounted) _avisar(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(seguimientoControllerProvider);
    final control = ref.read(seguimientoControllerProvider.notifier);
    final listo = switch (asincrono.value) {
      final SeguimientoListo s => s,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maktub Barbell Club'),
        actions: [
          if (listo != null)
            IconButton(
              tooltip: 'Temporizador',
              icon: const Icon(Icons.timer_outlined),
              onPressed: () async {
                final t = await elegirTemporizador(context, listo.datos.temporizadores.values);
                if (t != null) ref.read(cronoControllerProvider.notifier).iniciar(t);
              },
            ),
          IconButton(
            tooltip: 'Traer cambios',
            icon: const Icon(Icons.refresh),
            onPressed: () => _ejecutar(context, control.refrescar, 'Actualizado'),
          ),
        ],
      ),
      body: switch (asincrono) {
        AsyncValue(:final error?) when listo == null => _Mensaje(
            texto: 'No se pudo cargar.\n$error',
            accion: TextButton(onPressed: () => ref.invalidate(seguimientoControllerProvider), child: const Text('Reintentar')),
          ),
        AsyncValue(value: SeguimientoNoDisponible(:final mensaje)) => _Mensaje(texto: mensaje),
        _ when listo != null => _Contenido(estado: listo),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BarraCrono(),
          if (listo != null && !listo.sesion.estaVacia)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: listo.guardando ? null : () => _ejecutar(context, control.guardar, 'Guardado'),
                  child: Text(
                    listo.guardando
                        ? 'Guardando...'
                        : listo.sesion.registrada
                            ? 'Actualizar registro'
                            : 'Guardar día',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.estado});

  final SeguimientoListo estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.read(seguimientoControllerProvider.notifier);
    final s = estado.sesion;
    final tema = Theme.of(context);
    final indexados = [for (final (i, it) in s.items.indexed) (i, it)];

    Widget tarjeta((int, ItemCargado) x) => TarjetaEjercicio(
          key: ValueKey('${estado.claveActual}|${x.$1}|${x.$2.ejercicio.id}'),
          indice: x.$1,
          item: x.$2,
          ajusteSesion: s.ajuste,
          temporizadores: estado.datos.temporizadores,
        );

    final principal = indexados.where((x) => x.$2.bloque == Bloque.principal).toList();
    final cierre = indexados.where((x) => x.$2.bloque == Bloque.cierre).toList();
    final grupos = <int?, List<(int, ItemCargado)>>{};
    for (final x in cierre) {
      (grupos[x.$2.grupo] ??= []).add(x);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CabeceraSeguimiento(estado: estado),
        const Divider(height: 32),
        Text('Día ${s.dia}${s.primario == null ? '' : ' · ${s.primario!.nombre}'}', style: tema.textTheme.headlineSmall),
        Text.rich(TextSpan(
          style: tema.textTheme.bodyMedium,
          children: [
            TextSpan(text: '${estado.plan.nombre} · ciclo ${s.ciclo} · semana ${s.semana} de ${s.variante.etiqueta}'),
            if (s.registrada)
              TextSpan(
                text: ' · registrado',
                style: TextStyle(color: tema.colorScheme.primary, fontWeight: FontWeight.bold),
              ),
          ],
        )),
        const SizedBox(height: 8),
        ControlAjuste(titulo: 'Ajuste del día', valor: s.ajuste, onCambio: control.cambiarAjuste),
        if (s.estiramiento.isNotEmpty) ...[
          _Titulo(Bloque.estiramiento.etiqueta),
          for (final e in s.estiramiento) Text('• ${e.nombre}'),
        ],
        if (s.calentamiento.isNotEmpty) ...[
          _Titulo(Bloque.calentamiento.etiqueta),
          for (final e in s.calentamiento) Text('• ${e.nombre}'),
        ],
        if (principal.isNotEmpty) ...[
          _Titulo(Bloque.principal.etiqueta),
          for (final x in principal) tarjeta(x),
        ],
        if (cierre.isNotEmpty) ...[
          _Titulo(Bloque.cierre.etiqueta),
          for (final miembros in grupos.values) ...[
            if (etiquetaGrupo(miembros.length).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(etiquetaGrupo(miembros.length), style: tema.textTheme.labelLarge),
              ),
            for (final x in miembros) tarjeta(x),
          ],
        ],
        if (s.wod != null) ...[
          _Titulo(Bloque.wod.etiqueta),
          _TarjetaWod(wod: s.wod!, temporizadores: estado.datos.temporizadores),
        ],
        if (s.estaVacia)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              'No hay nada cargado para el día ${s.dia} en ${s.variante.etiqueta}.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _TarjetaWod extends ConsumerWidget {
  const _TarjetaWod({required this.wod, required this.temporizadores});

  final Wod wod;
  final Map<String, Temporizador> temporizadores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = temporizadores[wod.temporizador];
    return Card(
      child: ListTile(
        title: Text(wod.nombre),
        subtitle: Text([wod.formato ?? 'WoD', ?wod.descripcion].join('\n')),
        isThreeLine: wod.descripcion != null,
        trailing: t == null
            ? null
            : IconButton(
                tooltip: t.nombre,
                icon: const Icon(Icons.timer_outlined),
                onPressed: () => ref.read(cronoControllerProvider.notifier).iniciar(t),
              ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(texto, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(texto, textAlign: TextAlign.center), ?accion],
          ),
        ),
      );
}
