import '../modelos/temporizador.dart';

/// Un tramo de duración fija. Todo temporizador se expande a una lista de fases
/// y de ahí para abajo el motor es el mismo.
class Fase {
  const Fase({
    required this.etiqueta,
    required this.segundos,
    required this.ronda,
    required this.rondas,
    this.esTrabajo = false,
  });

  final String etiqueta;
  final int segundos;
  final int ronda;
  final int rondas;
  final bool esTrabajo;
}

/// countdown: una fase. emom: una por ronda. tabata: trabajo y descanso
/// alternados, **sin descanso al final**.
List<Fase> fasesDe(Temporizador t) {
  final rondas = t.rondas < 1 ? 1 : t.rondas;
  return switch (t.tipo) {
    TipoTemporizador.countdown => [
        Fase(etiqueta: 'Descanso', segundos: t.trabajoSeg, ronda: 1, rondas: 1),
      ],
    TipoTemporizador.emom => [
        for (var i = 1; i <= rondas; i++)
          Fase(etiqueta: 'Minuto $i', segundos: t.trabajoSeg, ronda: i, rondas: rondas, esTrabajo: true),
      ],
    TipoTemporizador.tabata => [
        for (var i = 1; i <= rondas; i++) ...[
          Fase(etiqueta: 'Trabajo', segundos: t.trabajoSeg, ronda: i, rondas: rondas, esTrabajo: true),
          if (i < rondas) Fase(etiqueta: 'Descanso', segundos: t.descansoSeg, ronda: i, rondas: rondas),
        ],
      ],
  };
}

/// "EMOM · 10 rondas de 01:00", para listar temporizadores.
String describirTemporizador(Temporizador t) => switch (t.tipo) {
      TipoTemporizador.emom => 'EMOM · ${t.rondas} rondas de ${reloj(t.trabajoSeg)}',
      TipoTemporizador.tabata =>
        'Tabata · ${t.rondas} rondas de ${t.trabajoSeg}s trabajo y ${t.descansoSeg}s descanso',
      TipoTemporizador.countdown => 'Cuenta regresiva · ${reloj(t.trabajoSeg)}',
    };

/// mm:ss
String reloj(int segundos) {
  final s = segundos < 0 ? 0 : segundos;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
