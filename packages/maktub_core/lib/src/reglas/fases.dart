import '../modelos/temporizador.dart';

/// Rondas que se expanden de un EMOM Death By: no tiene fin fijo, lo corta el atleta.
const maxRondasDeathBy = 60;

/// Un tramo. Todo temporizador se expande a una lista de fases y de ahí para abajo el motor es el mismo.
class Fase {
  const Fase({
    required this.etiqueta,
    required this.segundos,
    required this.ronda,
    required this.rondas,
    this.esTrabajo = false,
    this.serie = 1,
    this.series = 1,
    this.abierta = false,
    this.senalCadaSeg,
  });

  final String etiqueta;

  /// 0 en una fase [abierta].
  final int segundos;
  final int ronda;

  /// 0 si no hay una cantidad fija de rondas (Death By).
  final int rondas;
  final bool esTrabajo;
  final int serie;
  final int series;

  /// Sin duración fija: cuenta hacia arriba hasta que el atleta termina (for time sin tope).
  final bool abierta;
  final int? senalCadaSeg;

  Fase _deSerie(int serie, int series) => Fase(
    etiqueta: etiqueta,
    segundos: segundos,
    ronda: ronda,
    rondas: rondas,
    esTrabajo: esTrabajo,
    serie: serie,
    series: series,
    abierta: abierta,
    senalCadaSeg: senalCadaSeg,
  );

  Fase _conEtiqueta(String nueva) => Fase(
    etiqueta: nueva,
    segundos: segundos,
    ronda: ronda,
    rondas: rondas,
    esTrabajo: esTrabajo,
    serie: serie,
    series: series,
    abierta: abierta,
    senalCadaSeg: senalCadaSeg,
  );
}

/// Las fases de [t], con sus series y el descanso entre ellas. Tabata va **sin descanso al final**.
List<Fase> fasesDe(Temporizador t) {
  if (t.tipo == TipoTemporizador.mix) return _fasesDeMix(t);
  final una = _fasesDeUnaSerie(t);
  final series = t.series < 1 ? 1 : t.series;
  return [
    for (var s = 1; s <= series; s++) ...[
      for (final f in una) f._deSerie(s, series),
      if (s < series && t.descansoSeriesSeg > 0)
        Fase(etiqueta: 'Descanso entre series', segundos: t.descansoSeriesSeg, ronda: 1, rondas: 1, serie: s, series: series),
    ],
  ];
}

List<Fase> _fasesDeUnaSerie(Temporizador t) {
  final rondas = t.rondas < 1 ? 1 : t.rondas;
  return switch (t.tipo) {
    TipoTemporizador.countdown => [Fase(etiqueta: 'Descanso', segundos: t.trabajoSeg, ronda: 1, rondas: 1)],
    TipoTemporizador.trabajo => [
      Fase(etiqueta: 'Trabajo', segundos: t.trabajoSeg, ronda: 1, rondas: 1, esTrabajo: true),
    ],
    TipoTemporizador.emom => [
      for (var i = 1; i <= (t.deathBy ? maxRondasDeathBy : rondas); i++)
        Fase(
          etiqueta: 'Minuto $i',
          segundos: t.trabajoSeg,
          ronda: i,
          rondas: t.deathBy ? 0 : rondas,
          esTrabajo: true,
        ),
    ],
    TipoTemporizador.tabata => [
      for (var i = 1; i <= rondas; i++) ...[
        Fase(etiqueta: 'Trabajo', segundos: t.trabajoSeg, ronda: i, rondas: rondas, esTrabajo: true),
        if (i < rondas) Fase(etiqueta: 'Descanso', segundos: t.descansoSeg, ronda: i, rondas: rondas),
      ],
    ],
    TipoTemporizador.amrap => [
      Fase(etiqueta: 'AMRAP', segundos: t.trabajoSeg, ronda: 1, rondas: 1, esTrabajo: true),
    ],
    TipoTemporizador.forTime => [
      Fase(
        etiqueta: 'For Time',
        segundos: t.limiteSeg ?? 0,
        ronda: 1,
        rondas: 1,
        esTrabajo: true,
        abierta: t.limiteSeg == null,
        senalCadaSeg: t.senalCadaSeg,
      ),
    ],
    TipoTemporizador.mix => const [],
  };
}

List<Fase> _fasesDeMix(Temporizador t) {
  final vueltas = t.rondas < 1 ? 1 : t.rondas;
  return [
    for (var v = 1; v <= vueltas; v++)
      for (final b in t.bloques)
        if (b.tipo != TipoTemporizador.mix)
          for (final f in fasesDe(b))
            b.nombre.trim().isEmpty ? f : f._conEtiqueta('${b.nombre.trim()} · ${f.etiqueta}'),
  ];
}

/// Segundos totales, o null si no tiene fin fijo (for time sin tope o Death By).
int? duracionTotalSeg(Temporizador t) {
  if (_sinFin(t)) return null;
  return fasesDe(t).fold<int>(0, (suma, f) => suma + f.segundos);
}

bool _sinFin(Temporizador t) => switch (t.tipo) {
  TipoTemporizador.forTime => t.limiteSeg == null,
  TipoTemporizador.emom => t.deathBy,
  TipoTemporizador.mix => t.bloques.any(_sinFin),
  _ => false,
};

String _conSeries(String base, Temporizador t) => t.series > 1 ? '$base · ${t.series} series' : base;

/// "EMOM · 10 rondas de 01:00", para listar temporizadores.
String describirTemporizador(Temporizador t) => switch (t.tipo) {
  TipoTemporizador.emom => _conSeries(
    t.deathBy ? 'EMOM Death By · cada ${reloj(t.trabajoSeg)}' : 'EMOM · ${t.rondas} rondas de ${reloj(t.trabajoSeg)}',
    t,
  ),
  TipoTemporizador.tabata => _conSeries(
    'Tabata · ${t.rondas} rondas de ${t.trabajoSeg}s trabajo y ${t.descansoSeg}s descanso',
    t,
  ),
  TipoTemporizador.countdown => 'Cuenta regresiva · ${reloj(t.trabajoSeg)}',
  TipoTemporizador.trabajo => 'Trabajo · ${reloj(t.trabajoSeg)}',
  TipoTemporizador.amrap => _conSeries('AMRAP · ${reloj(t.trabajoSeg)}', t),
  TipoTemporizador.forTime => _conSeries(
    t.limiteSeg == null ? 'For Time · sin límite' : 'For Time · límite ${reloj(t.limiteSeg!)}',
    t,
  ),
  TipoTemporizador.mix =>
    'Mix · ${t.bloques.length} ${t.bloques.length == 1 ? 'bloque' : 'bloques'}${t.rondas > 1 ? ' × ${t.rondas}' : ''}',
};

/// mm:ss
String reloj(int segundos) {
  final s = segundos < 0 ? 0 : segundos;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
