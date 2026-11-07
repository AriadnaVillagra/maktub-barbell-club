import 'package:maktub_core/maktub_core.dart';

import '../entities/sesion_del_dia.dart';

/// Arma el día de un atleta a partir del plan activo, sus RMs y lo ya registrado.
/// Puro: no hace IO.
class ConstruirSesion {
  const ConstruirSesion();

  SesionDelDia call(
    SeguimientoSnapshot datos, {
    required String atletaId,
    required int ciclo,
    required int semana,
    required int dia,
  }) {
    final plan = datos.plan!;
    final atleta = datos.atletas.firstWhere((a) => a.id == atletaId);
    final variante = varianteDeSemana(semana, planTieneCarga2: plan.tieneCarga2);
    final planDia = plan.dia(dia);
    final contenido = planDia?.variantes[variante] ?? const ContenidoVariante();
    final registrada = sesionRegistrada(datos, atletaId: atletaId, ciclo: ciclo, semana: semana, dia: dia);

    final prescripciones = [...contenido.ejercicios]..sort(_porBloqueGrupoOrden);
    final items = [
      for (final p in prescripciones) _itemCargado(p, datos.ejercicios, atleta, registrada),
    ];

    final primario = datos.ejercicios[planDia?.primario] ??
        items.map((it) => it.ejercicio).where((e) => e.categoria == Categoria.primario).firstOrNull;

    return SesionDelDia(
      atletaId: atletaId,
      ciclo: ciclo,
      semana: semana,
      dia: dia,
      variante: variante,
      primario: primario,
      registrada: registrada != null,
      estiramiento: _sinCarga(Categoria.estiramiento, planDia?.estiramiento ?? const [], primario, datos.ejercicios),
      calentamiento: _sinCarga(Categoria.calentamiento, planDia?.calentamiento ?? const [], primario, datos.ejercicios),
      items: items,
      wod: datos.wods[contenido.wod],
    );
  }

  static int _porBloqueGrupoOrden(Prescripcion a, Prescripcion b) {
    final porBloque = (a.bloque == Bloque.principal ? 0 : 1).compareTo(b.bloque == Bloque.principal ? 0 : 1);
    if (porBloque != 0) return porBloque;
    final porGrupo = (a.grupo ?? 0).compareTo(b.grupo ?? 0);
    return porGrupo != 0 ? porGrupo : a.orden.compareTo(b.orden);
  }

  /// Explícitos en el plan o, si no hay, los del catálogo que acompañan al primario
  /// (misma referencia) más los que sirven para cualquier día (sin referencia).
  static List<Ejercicio> _sinCarga(
    Categoria categoria,
    List<String> explicitos,
    Ejercicio? primario,
    Map<String, Ejercicio> catalogo,
  ) {
    if (explicitos.isNotEmpty) {
      return [for (final id in explicitos) ?catalogo[id]];
    }
    final referencia = primario?.referencia;
    return [
      for (final e in catalogo.values)
        if (e.categoria == categoria && (e.referencia == null || e.referencia == referencia)) e,
    ];
  }

  static ItemCargado _itemCargado(
    Prescripcion p,
    Map<String, Ejercicio> catalogo,
    Atleta atleta,
    SesionRegistrada? registrada,
  ) {
    final ej = catalogo[p.ejercicio] ?? Ejercicio(id: p.ejercicio, nombre: p.ejercicio, categoria: Categoria.accesorio);

    final plantilla = [
      for (final (i, s) in p.series.indexed)
        () {
          final pct = normalizarPct(s.pct);
          final porRm = pct != null && ej.referencia != null;
          return SeriePlanificada(
            serie: i + 1,
            reps: s.reps,
            pctPlan: porRm ? pct : null,
            rm: porRm ? atleta.rmDe(ej.referencia!) : null,
            pesoFijo: porRm ? null : atleta.pesosAccesorios[ej.id],
          );
        }(),
    ];

    final previas = [
      for (final f in registrada?.filas ?? const <FilaRegistro>[])
        if (f.ejercicio == ej.id && f.bloque == p.bloque && f.serie != null) f,
    ]..sort((a, b) => a.serie!.compareTo(b.serie!));

    return ItemCargado(
      ejercicio: ej,
      bloque: p.bloque,
      grupo: p.grupo,
      rpe: p.rpe,
      temporizadorId: p.temporizador,
      plantilla: plantilla,
      series: previas.isEmpty
          ? ItemCargado.seriesDesdePlantilla(plantilla)
          : [
              for (final f in previas)
                SerieEnCurso(serie: f.serie!, reps: f.reps, pesoKg: f.pesoKg, hecha: true, tocada: true),
            ],
      nota: previas.firstOrNull?.nota ?? '',
    );
  }
}

SesionRegistrada? sesionRegistrada(
  SeguimientoSnapshot datos, {
  required String atletaId,
  required int ciclo,
  required int semana,
  required int dia,
}) {
  final plan = datos.plan;
  if (plan == null) return null;
  final clave = SesionRegistrada.claveSesion(atleta: atletaId, plan: plan.id, ciclo: ciclo, semana: semana, dia: dia);
  return datos.sesiones.where((s) => s.clave == clave).firstOrNull;
}
