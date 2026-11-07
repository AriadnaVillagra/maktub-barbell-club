import 'package:maktub_core/maktub_core.dart';

/// Estado inmutable de un temporizador en marcha. El tiempo se mide contra el
/// reloj del sistema ([fin]), no sumando ticks: si la pantalla se apaga, al
/// volver el número es el correcto.
class Crono {
  const Crono._({required this.temporizador, required this.fases, required this.indice, required this.fin, this.pausaSeg});

  /// Nulo si el temporizador no tiene duración cargada.
  static Crono? iniciar(Temporizador t, DateTime ahora) {
    final fases = fasesDe(t);
    if (fases.isEmpty || fases.first.segundos <= 0) return null;
    return Crono._(temporizador: t, fases: fases, indice: 0, fin: ahora.add(Duration(seconds: fases.first.segundos)));
  }

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

  int restantes(DateTime ahora) {
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
      fin: ahora.add(Duration(seconds: fases[siguiente].segundos)),
    );
  }

  Crono alternarPausa(DateTime ahora) => enPausa
      ? _con(fin: ahora.add(Duration(seconds: pausaSeg!)), pausaSeg: null)
      : _con(fin: fin, pausaSeg: restantes(ahora));

  /// ±30 s en una cuenta regresiva. Nunca queda por debajo de cero.
  Crono sumar(int segundos, DateTime ahora) {
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
