import 'package:maktub_core/maktub_core.dart';

/// Una serie tal como la prescribe el plan, ya resuelta para un atleta.
class SeriePlanificada {
  const SeriePlanificada({required this.serie, this.reps, this.pctPlan, this.rm, this.pesoFijo});

  final int serie;
  final int? reps;

  /// % del RM. No nulo si y solo si la serie carga por RM.
  final double? pctPlan;

  /// RM vigente del atleta para la referencia del ejercicio. Nulo si falta.
  final double? rm;

  /// Kilaje fijo del accesorio. Nulo si el atleta no lo tiene cargado.
  final double? pesoFijo;

  bool get porRm => pctPlan != null;

  double? pctAplicado(int ajuste) => porRm ? pctEfectivo(pctPlan!, ajuste) : null;

  double? peso(int ajuste, Equipo equipo) =>
      porRm ? pesoPorPorcentaje(rm: rm, pct: pctAplicado(ajuste)!, equipo: equipo) : pesoFijo;
}

/// Lo que el atleta va haciendo. Una serie [tocada] a mano no se recalcula al mover el ajuste.
class SerieEnCurso {
  const SerieEnCurso({required this.serie, this.reps, this.pesoKg, this.hecha = false, this.tocada = false});

  final int serie;
  final int? reps;

  /// Solo significativo si [tocada]; si no, el peso sale del plan.
  final double? pesoKg;
  final bool hecha;
  final bool tocada;

  SerieEnCurso copyWith({int? reps, double? pesoKg, bool? hecha, bool? tocada, bool borrarPeso = false, bool borrarReps = false}) =>
      SerieEnCurso(
        serie: serie,
        reps: borrarReps ? null : reps ?? this.reps,
        pesoKg: borrarPeso ? null : pesoKg ?? this.pesoKg,
        hecha: hecha ?? this.hecha,
        tocada: tocada ?? this.tocada,
      );
}

/// Serie resuelta para mostrar y registrar: combina lo planificado con lo hecho.
class SerieVista {
  const SerieVista({
    required this.serie,
    required this.reps,
    required this.pesoKg,
    required this.hecha,
    required this.tocada,
    required this.porRm,
    required this.rm,
    required this.pctAplicado,
  });

  final int serie;
  final int? reps;
  final double? pesoKg;
  final bool hecha;
  final bool tocada;
  final bool porRm;
  final double? rm;
  final double? pctAplicado;

  /// El % que se guarda tiene que concordar con el peso que se guarda, o la
  /// intensidad relativa del historial miente. Si el kilaje se escribió a mano, sale de ahí.
  double? get pctARegistrar {
    if (!porRm || rm == null) return null;
    if (tocada && pesoKg != null) return pctDesdePeso(pesoKg!, rm!);
    return pctAplicado;
  }
}

class ItemCargado {
  const ItemCargado({
    required this.ejercicio,
    required this.bloque,
    required this.plantilla,
    required this.series,
    this.grupo,
    this.rpe,
    this.temporizadorId,
    this.ajuste,
    this.nota = '',
  });

  final Ejercicio ejercicio;
  final Bloque bloque;
  final int? grupo;
  final String? rpe;
  final String? temporizadorId;

  /// Ajuste propio del ejercicio; nulo hereda el de la sesión.
  final int? ajuste;
  final List<SeriePlanificada> plantilla;
  final List<SerieEnCurso> series;
  final String nota;

  bool get cargaPorRm => plantilla.any((s) => s.porRm);

  int ajusteEfectivo(int ajusteSesion) => ajuste ?? ajusteSesion;

  SeriePlanificada? _planDe(int i) => plantilla.isEmpty ? null : plantilla[i < plantilla.length ? i : plantilla.length - 1];

  List<SerieVista> vista(int ajusteSesion, Equipo equipo) {
    final ajusteItem = ajusteEfectivo(ajusteSesion);
    return [
      for (final (i, s) in series.indexed)
        () {
          final plan = _planDe(i);
          return SerieVista(
            serie: s.serie,
            reps: s.reps,
            pesoKg: s.tocada ? s.pesoKg : plan?.peso(ajusteItem, equipo),
            hecha: s.hecha,
            tocada: s.tocada,
            porRm: plan?.porRm ?? false,
            rm: plan?.rm,
            pctAplicado: plan?.pctAplicado(ajusteItem),
          );
        }(),
    ];
  }

  /// Si lo que hay difiere de lo planificado (para ofrecer "volver a lo planificado").
  bool editado(int ajusteSesion, Equipo equipo) {
    if (series.length != plantilla.length) return true;
    final actual = vista(ajusteSesion, equipo);
    final ajusteItem = ajusteEfectivo(ajusteSesion);
    for (var i = 0; i < plantilla.length; i++) {
      if (actual[i].pesoKg != plantilla[i].peso(ajusteItem, equipo) || actual[i].reps != plantilla[i].reps) return true;
    }
    return false;
  }

  ItemCargado copyWith({List<SerieEnCurso>? series, String? nota, int? ajuste, bool heredarAjuste = false}) => ItemCargado(
        ejercicio: ejercicio,
        bloque: bloque,
        grupo: grupo,
        rpe: rpe,
        temporizadorId: temporizadorId,
        ajuste: heredarAjuste ? null : ajuste ?? this.ajuste,
        plantilla: plantilla,
        series: series ?? this.series,
        nota: nota ?? this.nota,
      );

  ItemCargado restaurado() => copyWith(series: seriesDesdePlantilla(plantilla));

  static List<SerieEnCurso> seriesDesdePlantilla(List<SeriePlanificada> plantilla) =>
      [for (final p in plantilla) SerieEnCurso(serie: p.serie, reps: p.reps)];
}

/// El día de un atleta: lo planificado resuelto con sus RMs, más lo que va haciendo.
class SesionDelDia {
  const SesionDelDia({
    required this.atletaId,
    required this.ciclo,
    required this.semana,
    required this.dia,
    required this.variante,
    this.primario,
    this.ajuste = Ajuste.neutro,
    this.registrada = false,
    this.estiramiento = const [],
    this.calentamiento = const [],
    this.items = const [],
    this.wod,
  });

  final String atletaId;
  final int ciclo;
  final int semana;
  final int dia;
  final Variante variante;
  final Ejercicio? primario;
  final int ajuste;
  final bool registrada;
  final List<Ejercicio> estiramiento;
  final List<Ejercicio> calentamiento;
  final List<ItemCargado> items;
  final Wod? wod;

  bool get estaVacia => items.isEmpty && wod == null;

  SesionDelDia copyWith({int? ajuste, List<ItemCargado>? items}) => SesionDelDia(
        atletaId: atletaId,
        ciclo: ciclo,
        semana: semana,
        dia: dia,
        variante: variante,
        primario: primario,
        ajuste: ajuste ?? this.ajuste,
        registrada: registrada,
        estiramiento: estiramiento,
        calentamiento: calentamiento,
        items: items ?? this.items,
        wod: wod,
      );

  SesionDelDia _conItem(int i, ItemCargado Function(ItemCargado) cambio) =>
      copyWith(items: [for (final (j, it) in items.indexed) j == i ? cambio(it) : it]);

  /// delta 0 vuelve a 100 %.
  SesionDelDia cambiarAjuste(int delta) => copyWith(ajuste: delta == 0 ? Ajuste.neutro : Ajuste.acotar(ajuste + delta));

  /// delta 0 vuelve a heredar el ajuste de la sesión.
  SesionDelDia cambiarAjusteItem(int i, int delta) => _conItem(
        i,
        (it) => delta == 0 ? it.copyWith(heredarAjuste: true) : it.copyWith(ajuste: Ajuste.acotar(it.ajusteEfectivo(ajuste) + delta)),
      );

  /// Editar peso o reps marca la serie como tocada y fija el peso que se veía,
  /// para que un cambio de ajuste posterior no la pise.
  SesionDelDia editarSerie(int i, int j, Equipo equipo, {double? pesoKg, int? reps, bool borrarPeso = false, bool borrarReps = false}) =>
      _conItem(i, (it) {
        final visible = it.vista(ajuste, equipo)[j];
        final series = [...it.series];
        series[j] = series[j].copyWith(
          tocada: true,
          pesoKg: pesoKg ?? visible.pesoKg,
          reps: reps,
          borrarPeso: borrarPeso,
          borrarReps: borrarReps,
        );
        return it.copyWith(series: series);
      });

  SesionDelDia alternarHecha(int i, int j) => _conItem(i, (it) {
        final series = [...it.series];
        series[j] = series[j].copyWith(hecha: !series[j].hecha);
        return it.copyWith(series: series);
      });

  SesionDelDia editarNota(int i, String nota) => _conItem(i, (it) => it.copyWith(nota: nota));

  SesionDelDia restaurar(int i) => _conItem(i, (it) => it.restaurado());
}
