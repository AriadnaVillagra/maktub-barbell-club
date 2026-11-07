import 'package:maktub_core/maktub_core.dart';

import '../entities/sesion_del_dia.dart';

/// Convierte la sesión en curso en el registro completo del día (no solo los desvíos).
class ArmarRegistro {
  const ArmarRegistro();

  SesionRegistrada call(SesionDelDia sesion, {required String planId, required DateTime fecha, required Equipo equipo}) {
    final filas = <FilaRegistro>[
      for (final e in sesion.estiramiento) FilaRegistro(ejercicio: e.id, bloque: Bloque.estiramiento),
      for (final e in sesion.calentamiento) FilaRegistro(ejercicio: e.id, bloque: Bloque.calentamiento),
      for (final it in sesion.items)
        for (final s in it.vista(sesion.ajuste, equipo))
          FilaRegistro(
            ejercicio: it.ejercicio.id,
            bloque: it.bloque,
            serie: s.serie,
            pesoKg: s.pesoKg,
            reps: s.reps,
            rmVigente: s.porRm ? s.rm : null,
            pct: s.pctARegistrar,
            nota: it.nota.trim().isEmpty ? null : it.nota.trim(),
          ),
      if (sesion.wod != null) FilaRegistro(ejercicio: sesion.wod!.id, bloque: Bloque.wod),
    ];

    return SesionRegistrada(
      atleta: sesion.atletaId,
      plan: planId,
      ciclo: sesion.ciclo,
      semana: sesion.semana,
      dia: sesion.dia,
      fecha: fecha,
      filas: filas,
    );
  }
}
