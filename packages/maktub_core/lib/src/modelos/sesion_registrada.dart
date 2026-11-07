import '../reglas/fechas.dart';
import 'enums.dart';
import 'json.dart';

/// Lo que un atleta hizo un día. Guarda el día entero, desnormalizado a propósito:
/// kilos en números más el RM y el % vigentes, nunca punteros al plan.
///
/// Invariante: `rmVigente × pct / 100 ≈ pesoKg` en toda fila con carga por RM.
class SesionRegistrada {
  const SesionRegistrada({
    required this.atleta,
    required this.plan,
    required this.ciclo,
    required this.semana,
    required this.dia,
    required this.fecha,
    this.filas = const [],
  });

  final String atleta;
  final String plan;

  /// Repetición del mes modelo. Sin ella el mes 2 pisaría al mes 1.
  final int ciclo;
  final int semana;
  final int dia;
  final DateTime fecha;
  final List<FilaRegistro> filas;

  /// Identifica unívocamente el día: guardar de nuevo reemplaza la sesión.
  String get clave => claveSesion(atleta: atleta, plan: plan, ciclo: ciclo, semana: semana, dia: dia);

  static String claveSesion({
    required String atleta,
    required String plan,
    required int ciclo,
    required int semana,
    required int dia,
  }) =>
      '$atleta|$plan|$ciclo|$semana|$dia';

  /// Errores de forma; vacío si la sesión es válida.
  List<String> validar() => [
        if (atleta.isEmpty) 'falta el atleta',
        if (plan.isEmpty) 'falta el plan',
        if (ciclo < 1) 'el ciclo debe ser 1 o más',
        if (semana < 1 || semana > 4) 'la semana debe estar entre 1 y 4',
        if (dia < 1 || dia > 7) 'el día debe estar entre 1 y 7',
      ];

  factory SesionRegistrada.fromJson(Json j) => SesionRegistrada(
        atleta: '${j['atleta'] ?? ''}',
        plan: '${j['plan'] ?? ''}',
        ciclo: enteroOpcional(j['ciclo']) ?? 1,
        semana: enteroOpcional(j['semana']) ?? 0,
        dia: enteroOpcional(j['dia']) ?? 0,
        fecha: desdeIsoFechaOpcional(j['fecha']) ?? hoy(),
        filas: [for (final f in listaJson(j['filas'])) FilaRegistro.fromJson(f)],
      );

  Json toJson() => {
        'atleta': atleta,
        'plan': plan,
        'ciclo': ciclo,
        'semana': semana,
        'dia': dia,
        'fecha': aIsoFecha(fecha),
        'filas': [for (final f in filas) f.toJson()],
      };
}

class FilaRegistro {
  const FilaRegistro({
    required this.ejercicio,
    required this.bloque,
    this.serie,
    this.pesoKg,
    this.reps,
    this.rmVigente,
    this.pct,
    this.nota,
  });

  /// Id del ejercicio (o del WoD en el bloque `wod`).
  final String ejercicio;
  final Bloque bloque;
  final int? serie;
  final double? pesoKg;
  final int? reps;
  final double? rmVigente;
  final double? pct;
  final String? nota;

  factory FilaRegistro.fromJson(Json j) => FilaRegistro(
        ejercicio: '${j['ejercicio']}',
        bloque: Bloque.desdeCable(j['bloque']),
        serie: enteroOpcional(j['serie']),
        pesoKg: numOpcional(j['pesoKg']),
        reps: enteroOpcional(j['reps']),
        rmVigente: numOpcional(j['rmVigente']),
        pct: numOpcional(j['pct']),
        nota: textoOpcional(j['nota']),
      );

  Json toJson() => sinNulos({
        'ejercicio': ejercicio,
        'bloque': bloque.cable,
        'serie': serie,
        'pesoKg': pesoKg,
        'reps': reps,
        'rmVigente': rmVigente,
        'pct': pct,
        'nota': nota,
      });
}
