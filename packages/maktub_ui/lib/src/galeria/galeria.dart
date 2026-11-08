import 'package:flutter/material.dart';

import '../componentes/campo_busqueda.dart';
import '../componentes/contador_cantidad.dart';
import '../componentes/insignia.dart';
import '../componentes/lista_de_problemas.dart';
import '../componentes/sign_in_panel.dart';
import '../tema/contexto.dart';
import '../tema/modo.dart';
import '../tema/tema_maktub.dart';
import '../tokens/colores.dart';
import '../tokens/contraste.dart';
import '../tokens/densidad.dart';
import '../tokens/primitivos.dart';

/// Galería del sistema de diseño: cada token y componente en los dos temas y las dos
/// densidades. Es la referencia viva del sistema. Todo componente nuevo agrega su sección.
class GaleriaMaktub extends StatefulWidget {
  const GaleriaMaktub({super.key});

  @override
  State<GaleriaMaktub> createState() => _GaleriaMaktubState();
}

class _GaleriaMaktubState extends State<GaleriaMaktub> {
  var _brillo = Brightness.dark;
  var _densidad = Densidad.planificacion;

  @override
  Widget build(BuildContext context) => Theme(
        data: TemaMaktub.para(_brillo, _densidad),
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Galería'),
              actions: [
                SegmentedButton<Brightness>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Brightness.dark, icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(value: Brightness.light, icon: Icon(Icons.light_mode_outlined)),
                  ],
                  selected: {_brillo},
                  onSelectionChanged: (s) => setState(() => _brillo = s.single),
                ),
                const SizedBox(width: Espacio.s),
                SegmentedButton<Densidad>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Densidad.planificacion, label: Text('Plan')),
                    ButtonSegment(value: Densidad.entrenamiento, label: Text('Entreno')),
                  ],
                  selected: {_densidad},
                  onSelectionChanged: (s) => setState(() => _densidad = s.single),
                ),
                const SizedBox(width: Espacio.s),
              ],
            ),
            body: const SingleChildScrollView(child: Muestrario()),
          ),
        ),
      );
}

/// Todas las secciones de la galería, con el tema que haya arriba. Lo usan los goldens.
class Muestrario extends StatelessWidget {
  const Muestrario({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Seccion('Colores de Material', _ColoresMaterial()),
            _Seccion('Colores propios', _ColoresPropios()),
            _Seccion('Texto', _Textos()),
            _Seccion('Números', _Numeros()),
            _Seccion('Controles', _Controles()),
            _Seccion('Ingreso', _Ingreso()),
            _Seccion('Insignias', _Insignias()),
            _Seccion('Búsqueda y cantidad', _BusquedaYCantidad()),
            _Seccion('Lista de problemas', _ListaDeProblemas()),
          ],
        ),
      );
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo, this.contenido);

  final String titulo;
  final Widget contenido;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espacio.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: context.textos.titleLarge),
            const Divider(),
            contenido,
          ],
        ),
      );
}

/// Muestra de un par fondo/contenido con su relación de contraste.
class _Muestra extends StatelessWidget {
  const _Muestra(this.nombre, this.par);

  final String nombre;
  final ParColor par;

  @override
  Widget build(BuildContext context) => Container(
        width: 148,
        height: 72,
        padding: const EdgeInsets.all(Espacio.s),
        decoration: BoxDecoration(
          color: par.fondo,
          borderRadius: const BorderRadius.all(Radius.circular(Radios.chico)),
          border: Border.all(color: context.esquema.outlineVariant),
        ),
        child: DefaultTextStyle(
          style: context.textos.labelMedium!.copyWith(color: par.sobre),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${contraste(par.sobre, par.fondo).toStringAsFixed(1)}:1'),
            ],
          ),
        ),
      );
}

class _ColoresMaterial extends StatelessWidget {
  const _ColoresMaterial();

  @override
  Widget build(BuildContext context) {
    final e = context.esquema;
    return Wrap(
      spacing: Espacio.s,
      runSpacing: Espacio.s,
      children: [
        _Muestra('surface', ParColor(e.surface, e.onSurface)),
        _Muestra('surfaceContainer', ParColor(e.surfaceContainer, e.onSurface)),
        _Muestra('surfaceContainerHighest', ParColor(e.surfaceContainerHighest, e.onSurfaceVariant)),
        _Muestra('primary', ParColor(e.primary, e.onPrimary)),
        _Muestra('primaryContainer', ParColor(e.primaryContainer, e.onPrimaryContainer)),
        _Muestra('secondaryContainer', ParColor(e.secondaryContainer, e.onSecondaryContainer)),
        _Muestra('tertiaryContainer', ParColor(e.tertiaryContainer, e.onTertiaryContainer)),
        _Muestra('error', ParColor(e.error, e.onError)),
        _Muestra('errorContainer', ParColor(e.errorContainer, e.onErrorContainer)),
        _Muestra('inverseSurface', ParColor(e.inverseSurface, e.onInverseSurface)),
      ],
    );
  }
}

class _ColoresPropios extends StatelessWidget {
  const _ColoresPropios();

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Wrap(
      spacing: Espacio.s,
      runSpacing: Espacio.s,
      children: [
        _Muestra('boton primario', c.botonPrimario),
        _Muestra('enfasis (texto)', ParColor(context.esquema.surface, c.enfasis)),
        _Muestra('acento', ParColor.auto(c.acento)),
        _Muestra('exito', c.exito),
        _Muestra('alerta', c.alerta),
        _Muestra('serie hecha', c.serieHecha),
        _Muestra('serie pendiente', c.seriePendiente),
        _Muestra('turno activo', c.turnoActivo),
        _Muestra('insignia base', c.insigniaBase),
        _Muestra('insignia propio', c.insigniaPropio),
        for (var z = 1; z <= 5; z++) _Muestra('zona $z', c.zona(z)),
        for (final kg in c.discos.keys) _Muestra('disco $kg kg', c.disco(kg)),
      ],
    );
  }
}

class _Textos extends StatelessWidget {
  const _Textos();

  @override
  Widget build(BuildContext context) {
    final t = context.textos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (nombre, estilo) in [
          ('headlineMedium', t.headlineMedium),
          ('titleLarge', t.titleLarge),
          ('titleMedium', t.titleMedium),
          ('bodyLarge', t.bodyLarge),
          ('bodyMedium', t.bodyMedium),
          ('labelLarge', t.labelLarge),
          ('bodySmall', t.bodySmall),
        ])
          Text('$nombre · Sentadilla 5 × 3', style: estilo),
      ],
    );
  }
}

class _Numeros extends StatelessWidget {
  const _Numeros();

  @override
  Widget build(BuildContext context) {
    final n = context.numeros;
    return Wrap(
      spacing: Espacio.xl,
      runSpacing: Espacio.s,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text('102.5', style: n.peso),
        Text('01:30', style: n.reloj),
        Text('11.1', style: n.grande),
        Text('85%', style: n.medio),
        Text('3 × 5', style: n.chico),
      ],
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: context.densidad.separacion,
        runSpacing: context.densidad.separacion,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(onPressed: () {}, child: const Text('Primario')),
          OutlinedButton(onPressed: () {}, child: const Text('Secundario')),
          TextButton(onPressed: () {}, child: const Text('Texto')),
          const FilledButton(onPressed: null, child: Text('Deshabilitado')),
          IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          IconButton.filled(onPressed: () {}, icon: const Icon(Icons.timer_outlined)),
          FilterChip(label: const Text('Fuerza'), selected: true, onSelected: (_) {}),
          FilterChip(label: const Text('Cardio'), selected: false, onSelected: (_) {}),
          Switch(value: true, onChanged: (_) {}),
          const SizedBox(width: 280, child: TextField(decoration: InputDecoration(labelText: 'Ejercicio'))),
          const SizedBox(
            width: 320,
            child: Card(
              child: ListTile(
                leading: Icon(Icons.fitness_center),
                title: Text('Sentadilla'),
                subtitle: Text('5 series · 80 % del RM'),
              ),
            ),
          ),
          Text('Densidad: ${context.densidad.name} · táctil ${context.densidad.tactilMinimo.round()} dp',
              style: context.textos.bodySmall),
        ],
      );
}

/// [SignInPanel] with a stand-in for Google's button (the real one is an HTML element) and a
/// failure message.
class _Ingreso extends StatelessWidget {
  const _Ingreso();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Espacio.xxl,
        runSpacing: Espacio.xl,
        children: [
          SignInPanel(
            title: 'Maktub Barbell Club',
            subtitle: 'Ingresá con tu cuenta de Google.',
            action: OutlinedButton(onPressed: () {}, child: const Text('Botón de Google')),
          ),
          SignInPanel(
            title: 'Maktub Barbell Club',
            action: OutlinedButton(onPressed: () {}, child: const Text('Botón de Google')),
            message: 'Este email no tiene una cuenta en Maktub. Pedile acceso a tu coach.',
          ),
          const SignInPanel(title: 'Enviando', action: SizedBox.shrink(), busy: true),
        ],
      );
}

/// Atajo para montar la galería con el tema de un modo (p. ej. en una ruta de desarrollo).
class GaleriaDeModo extends StatelessWidget {
  const GaleriaDeModo({super.key, this.modo = ModoApp.planificacion});

  final ModoApp modo;

  @override
  Widget build(BuildContext context) => TemaDeModo(modo: modo, child: const GaleriaMaktub());
}

class _BusquedaYCantidad extends StatelessWidget {
  const _BusquedaYCantidad();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Espacio.l,
        runSpacing: Espacio.m,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 280, child: CampoBusqueda(hint: 'Buscar ejercicio', onChanged: (_) {})),
          ContadorCantidad(valor: 3, onChanged: (_) {}),
        ],
      );
}

class _Insignias extends StatelessWidget {
  const _Insignias();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Espacio.s,
        runSpacing: Espacio.s,
        children: [
          InsigniaMaktub('Default', context.colores.insigniaBase),
          InsigniaMaktub('Custom', context.colores.insigniaPropio),
        ],
      );
}

class _ListaDeProblemas extends StatelessWidget {
  const _ListaDeProblemas();

  @override
  Widget build(BuildContext context) => const ListaDeProblemas(
        titulo: 'El plan tiene 2 problemas; no se guardó.',
        problemas: [
          ProblemaMaktub('Falta el % de la serie.', ubicacion: 'Modelo A › Día 2 › Bloque 1 › Sentadilla › Serie 3'),
          ProblemaMaktub('El plan no tiene nombre.'),
        ],
      );
}
