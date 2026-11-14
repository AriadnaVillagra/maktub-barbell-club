import 'package:maktub_core/maktub_core.dart';

/// Estado inmutable de un temporizador en marcha. El tiempo se mide contra el
/// reloj del sistema ([fin]), no sumando ticks: si la pantalla se apaga, al
/// volver el número es el correcto.
class Crono {
  const Crono._({required this.temporizador, required this.fases, required this.indice, required this.fin, this.pausaSeg});

  /// Nulo si el temporizador no tiene duración cargada.
  static Crono? iniciar(Temporizador t, DateTime ahora) {
    final fases = fasesDe(t);
    if (fases.isEmpty || (!fases.first.abierta && fases.first.segundos <= 0)) return null;
    return Crono._(temporizador: t, fases: fases, indice: 0, fin: _finDe(fases.first, ahora));
  }

  /// Fin de una fase que empieza en [ahora]. En una fase abierta no hay fin: el campo guarda el instante en que
  /// empezó, y la cuenta va hacia arriba.
  static DateTime _finDe(Fase fase, DateTime ahora) =>
      fase.abierta ? ahora : ahora.add(Duration(seconds: fase.segundos));

  final Temporizador temporizador;
  final List<Fase> fases;
  final int indice;
  final DateTime fin;

  /// Segundos que quedaban al pausar; nulo si está corriendo.
  final int? pausaSeg;

  Fase get fase => fases[indice];
  bool get enPausa => pausaSeg != null;
  bool get porRondas => fases.length > 1;
  bool get esUltimaFase => indice == fases.length - 1;

  /// Sin duración fija (for time sin tope): cuenta hacia arriba hasta que el atleta termina.
  bool get abierta => fase.abierta;

  /// El atleta puede dar por terminado el trabajo antes del fin: for time y Death By.
  bool get sePuedeTerminar =>
      fase.esTrabajo && (fase.abierta || fase.rondas == 0 || temporizador.tipo == TipoTemporizador.forTime);

  /// Segundos que lleva la fase. En una fase abierta es lo que se muestra; en las demás, lo que ya pasó de su duración.
  int transcurridos(DateTime ahora) {
    if (fase.abierta) {
      if (pausaSeg != null) return pausaSeg!;
      final ms = ahora.difference(fin).inMilliseconds;
      return ms <= 0 ? 0 : ms ~/ 1000;
    }
    final pasados = fase.segundos - restantes(ahora);
    return pasados < 0 ? 0 : pasados;
  }

  /// El número que se pinta: lo que queda, o lo que va en una fase abierta.
  int visibles(DateTime ahora) => fase.abierta ? transcurridos(ahora) : restantes(ahora);

  /// Lo que queda de la fase; 0 en una fase abierta, que no termina sola.
  int restantes(DateTime ahora) {
    if (fase.abierta) return 0;
    if (pausaSeg != null) return pausaSeg!;
    final ms = fin.difference(ahora).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// La fase siguiente, o nulo si terminó.
  Crono? avanzar(DateTime ahora) {
    if (esUltimaFase) return null;
    final siguiente = indice + 1;
    return Crono._(
      temporizador: temporizador,
      fases: fases,
      indice: siguiente,
      fin: _finDe(fases[siguiente], ahora),
    );
  }

  Crono alternarPausa(DateTime ahora) {
    if (fase.abierta) {
      return enPausa
          ? _con(fin: ahora.subtract(Duration(seconds: pausaSeg!)), pausaSeg: null)
          : _con(fin: fin, pausaSeg: transcurridos(ahora));
    }
    return enPausa
        ? _con(fin: ahora.add(Duration(seconds: pausaSeg!)), pausaSeg: null)
        : _con(fin: fin, pausaSeg: restantes(ahora));
  }

  /// ±30 s en una cuenta regresiva. Nunca queda por debajo de cero. En una fase abierta no hace nada.
  Crono sumar(int segundos, DateTime ahora) {
    if (fase.abierta) return this;
    if (enPausa) {
      final nuevo = pausaSeg! + segundos;
      return _con(fin: fin, pausaSeg: nuevo < 0 ? 0 : nuevo);
    }
    final nuevoFin = fin.add(Duration(seconds: segundos));
    return _con(fin: nuevoFin.isBefore(ahora) ? ahora : nuevoFin, pausaSeg: null);
  }

  Crono _con({required DateTime fin, required int? pausaSeg}) =>
      Crono._(temporizador: temporizador, fases: fases, indice: indice, fin: fin, pausaSeg: pausaSeg);
}
