import 'package:maktub_core/maktub_core.dart';

import '../../domain/entities/sesion_del_dia.dart';
import '../../domain/usecases/construir_sesion.dart';

sealed class EstadoSeguimiento {
  const EstadoSeguimiento();
}

/// No hay con qué armar un día (sin plan activo, sin atletas o sin días).
class SeguimientoNoDisponible extends EstadoSeguimiento {
  const SeguimientoNoDisponible(this.mensaje);

  final String mensaje;
}

class SeguimientoListo extends EstadoSeguimiento {
  const SeguimientoListo({
    required this.datos,
    required this.atletaId,
    required this.fecha,
    required this.ciclo,
    required this.semana,
    required this.dia,
    this.borradores = const {},
    this.guardando = false,
  });

  final SeguimientoSnapshot datos;
  final String atletaId;
  final DateTime fecha;
  final int ciclo;
  final int semana;
  final int dia;

  /// Sesiones en curso por atleta/ciclo/semana/día: cambiar de día no pierde lo cargado.
  final Map<String, SesionDelDia> borradores;
  final bool guardando;

  Plan get plan => datos.plan!;

  String get claveActual => claveBorrador(atletaId, ciclo, semana, dia);

  SesionDelDia get sesion => borradores[claveActual]!;

  static String claveBorrador(String atleta, int ciclo, int semana, int dia) => '$atleta|$ciclo|$semana|$dia';

  bool diaRegistrado(int semana, int dia) =>
      sesionRegistrada(datos, atletaId: atletaId, ciclo: ciclo, semana: semana, dia: dia) != null;

  bool semanaCompleta(int semana) => plan.numerosDeDia.every((d) => diaRegistrado(semana, d));

  Variante varianteDe(int semana) => varianteDeSemana(semana, planTieneCarga2: plan.tieneCarga2);

  SeguimientoListo copyWith({
    SeguimientoSnapshot? datos,
    String? atletaId,
    DateTime? fecha,
    int? ciclo,
    int? semana,
    int? dia,
    Map<String, SesionDelDia>? borradores,
    bool? guardando,
  }) =>
      SeguimientoListo(
        datos: datos ?? this.datos,
        atletaId: atletaId ?? this.atletaId,
        fecha: fecha ?? this.fecha,
        ciclo: ciclo ?? this.ciclo,
        semana: semana ?? this.semana,
        dia: dia ?? this.dia,
        borradores: borradores ?? this.borradores,
        guardando: guardando ?? this.guardando,
      );
}
