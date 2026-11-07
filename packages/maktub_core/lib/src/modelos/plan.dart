import '../reglas/fechas.dart';
import 'enums.dart';
import 'json.dart';

/// Un plan es un mes modelo de cuatro semanas que se repite desde [inicio].
class Plan {
  const Plan({
    required this.id,
    required this.nombre,
    this.activo = false,
    this.inicio,
    this.dias = const [],
  });

  final String id;
  final String nombre;
  final bool activo;
  final DateTime? inicio;
  final List<PlanDia> dias;

  /// La semana 3 usa `carga2` solo si el plan la define en algún día.
  bool get tieneCarga2 => dias.any((d) => d.variantes[Variante.carga2]?.estaVacio == false);

  List<int> get numerosDeDia => [for (final d in dias) d.dia]..sort();

  PlanDia? dia(int numero) {
    for (final d in dias) {
      if (d.dia == numero) return d;
    }
    return null;
  }

  factory Plan.fromJson(Json j) => Plan(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        activo: j['activo'] == true,
        inicio: desdeIsoFechaOpcional(j['inicio']),
        dias: [for (final d in listaJson(j['dias'])) PlanDia.fromJson(d)],
      );

  Json toJson() => sinNulos({
        'id': id,
        'nombre': nombre,
        'activo': activo,
        'inicio': inicio == null ? null : aIsoFecha(inicio!),
        'dias': [for (final d in dias) d.toJson()],
      });
}

/// Un día del mes modelo. Estiramiento y calentamiento vacíos se deducen del
/// catálogo según la referencia del [primario].
class PlanDia {
  const PlanDia({
    required this.dia,
    this.primario,
    this.estiramiento = const [],
    this.calentamiento = const [],
    this.variantes = const {},
  });

  final int dia;

  /// Id del ejercicio primario del día.
  final String? primario;
  final List<String> estiramiento;
  final List<String> calentamiento;
  final Map<Variante, ContenidoVariante> variantes;

  factory PlanDia.fromJson(Json j) => PlanDia(
        dia: enteroOpcional(j['dia']) ?? 0,
        primario: textoOpcional(j['primario']),
        estiramiento: [for (final e in (j['estiramiento'] as List? ?? const [])) '$e'],
        calentamiento: [for (final e in (j['calentamiento'] as List? ?? const [])) '$e'],
        variantes: {
          for (final e in ((j['variantes'] as Map?) ?? const {}).entries)
            Variante.desdeCable(e.key): ContenidoVariante.fromJson((e.value as Map).cast()),
        },
      );

  Json toJson() => sinNulos({
        'dia': dia,
        'primario': primario,
        'estiramiento': estiramiento,
        'calentamiento': calentamiento,
        'variantes': {for (final e in variantes.entries) e.key.cable: e.value.toJson()},
      });
}

/// Lo que se hace un día en una variante (descarga / carga / carga2).
class ContenidoVariante {
  const ContenidoVariante({this.ejercicios = const [], this.wod});

  final List<Prescripcion> ejercicios;

  /// Id del [Wod] asignado, si hay.
  final String? wod;

  bool get estaVacio => ejercicios.isEmpty && wod == null;

  factory ContenidoVariante.fromJson(Json j) => ContenidoVariante(
        ejercicios: [for (final p in listaJson(j['ejercicios'])) Prescripcion.fromJson(p)],
        wod: textoOpcional(j['wod']),
      );

  Json toJson() => sinNulos({
        'ejercicios': [for (final p in ejercicios) p.toJson()],
        'wod': wod,
      });
}

/// Un ejercicio prescripto con sus series una por una (así se representan las rampas).
class Prescripcion {
  const Prescripcion({
    required this.bloque,
    required this.orden,
    required this.ejercicio,
    required this.series,
    this.grupo,
    this.rpe,
    this.temporizador,
  }) : assert(bloque == Bloque.principal || bloque == Bloque.cierre);

  final Bloque bloque;

  /// En el bloque final, ejercicios con el mismo grupo forman una serie conjunta
  /// (biserie, triserie...). El tamaño es libre.
  final int? grupo;
  final int orden;

  /// Id del ejercicio.
  final String ejercicio;
  final List<SeriePlan> series;

  /// Nota de texto que la app muestra pero no interpreta.
  final String? rpe;

  /// Id del temporizador de descanso.
  final String? temporizador;

  factory Prescripcion.fromJson(Json j) => Prescripcion(
        bloque: Bloque.desdeCable(j['bloque']),
        grupo: enteroOpcional(j['grupo']),
        orden: enteroOpcional(j['orden']) ?? 0,
        ejercicio: '${j['ejercicio']}',
        series: [for (final s in listaJson(j['series'])) SeriePlan.fromJson(s)],
        rpe: textoOpcional(j['rpe']),
        temporizador: textoOpcional(j['temporizador']),
      );

  Json toJson() => sinNulos({
        'bloque': bloque.cable,
        'grupo': grupo,
        'orden': orden,
        'ejercicio': ejercicio,
        'series': [for (final s in series) s.toJson()],
        'rpe': rpe,
        'temporizador': temporizador,
      });
}

class SeriePlan {
  const SeriePlan({this.reps, this.pct});

  final int? reps;

  /// Porcentaje del RM (65 = 65 %). Nulo en ejercicios de kilaje fijo.
  final double? pct;

  factory SeriePlan.fromJson(Json j) =>
      SeriePlan(reps: enteroOpcional(j['reps']), pct: numOpcional(j['pct']));

  Json toJson() => sinNulos({'reps': reps, 'pct': pct});
}
