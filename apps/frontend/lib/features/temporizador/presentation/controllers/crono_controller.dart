import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../domain/crono.dart';
import '../../domain/crono_result.dart';
import '../../domain/timer_cues.dart';
import '../../domain/timer_platform.dart';
import '../providers.dart';

/// Lo que la barra del temporizador pinta.
class VistaCrono {
  const VistaCrono(this.crono, this.segundos);

  final Crono crono;

  /// Lo que queda de la fase, o lo que lleva si es abierta.
  final int segundos;
}

final cronoControllerProvider = NotifierProvider<CronoController, VistaCrono?>(CronoController.new);

// Sound and vibration of each warning: the last 3 seconds, a phase change, the end.
const _beepTick = (hz: 880.0, duration: Duration(milliseconds: 100), vibrate: [40]);
const _beepPhase = (hz: 660.0, duration: Duration(milliseconds: 250), vibrate: [120]);
const _beepEnd = (hz: 990.0, duration: Duration(milliseconds: 700), vibrate: [200, 100, 200]);

typedef _Aviso = ({double hz, Duration duration, List<int> vibrate});

_Aviso _avisoDe(TimerCue cue) => switch (cue) {
  TimerCue.tick => _beepTick,
  TimerCue.phase => _beepPhase,
  TimerCue.end => _beepEnd,
};

/// Avisos con sonido y vibración (los últimos 3 segundos, el cambio de fase y el final) y pantalla encendida mientras
/// corre. Todo lo que pide al dispositivo puede fallar: el temporizador sigue igual.
///
/// Los sonidos se agendan en el dispositivo cada vez que el temporizador cambia ([cuesAhead]), así suenan con la app en
/// segundo plano, donde el tic se frena. El tic solo vibra (en primer plano) y pasa de fase; si estuvo frenado, pasa
/// todas las fases vencidas de una vez y sin repetir sonidos.
class CronoController extends Notifier<VistaCrono?> {
  Timer? _tic;
  int? _ultimoAviso;
  int? _ultimaSenal;

  /// Reloj inyectable para tests.
  DateTime Function() ahora = DateTime.now;

  @override
  VistaCrono? build() {
    ref.onDispose(() => _tic?.cancel());
    return null;
  }

  /// Devuelve false si el temporizador no tiene duración cargada.
  bool iniciar(Temporizador t) {
    final crono = Crono.iniciar(t, ahora());
    if (crono == null) return false;
    _tic?.cancel();
    _ultimoAviso = null;
    _ultimaSenal = null;
    ref.read(cronoResultsProvider.notifier).clear();
    _publicar(crono);
    _seguro((p) => p.start());
    _tic = Timer.periodic(const Duration(milliseconds: 200), (_) => _tictac());
    return true;
  }

  void alternarPausa() => _cambiar((c) => c.alternarPausa(ahora()));

  void sumar(int segundos) {
    _ultimoAviso = null;
    _cambiar((c) => c.sumar(segundos, ahora()));
  }

  /// El atleta terminó el trabajo (for time, Death By): guarda lo que tardó y sigue con la fase siguiente, o cierra si
  /// era la última. Devuelve lo guardado, o nulo si la fase no es de trabajo.
  CronoResult? terminar() {
    final crono = state?.crono;
    if (crono == null) return null;
    final fase = crono.fase;
    CronoResult? resultado;
    if (fase.esTrabajo) {
      resultado = CronoResult(
        timerId: crono.temporizador.id,
        timerName: crono.temporizador.nombre,
        label: fase.etiqueta,
        set: fase.serie,
        round: fase.ronda,
        seconds: crono.transcurridos(ahora()),
        at: ahora(),
      );
      ref.read(cronoResultsProvider.notifier).add(resultado);
    }
    // Death By ends when the athlete stops; a for time goes on to its rest or its next set.
    if (fase.rondas == 0) {
      _avisar(_beepEnd);
      detener();
    } else {
      _avanzar(crono);
    }
    return resultado;
  }

  /// Cierra el temporizador y cancela sus sonidos agendados (uno que ya está sonando, como el del final, termina).
  void detener() {
    _tic?.cancel();
    _tic = null;
    state = null;
    _seguro((p) => p.stop());
  }

  void _tictac() {
    var crono = state?.crono;
    if (crono == null || crono.enPausa) return;
    final ahoraMs = ahora();

    // Las fases vencidas (varias, si el tic estuvo frenado en segundo plano). Su sonido ya estaba agendado.
    if (!crono.abierta && crono.restantes(ahoraMs) <= 0) {
      var vencidas = 0;
      while (crono != null && !crono.abierta && crono.restantes(ahoraMs) <= 0) {
        crono = crono.avanzar(ahoraMs);
        vencidas++;
      }
      if (crono == null) {
        if (vencidas == 1) _vibrar(_beepEnd);
        detener();
        return;
      }
      if (vencidas == 1) _vibrar(_beepPhase);
      _ultimoAviso = null;
      _ultimaSenal = null;
      _publicar(crono, agendar: false);
      return;
    }

    if (!crono.abierta) {
      final quedan = crono.restantes(ahoraMs);
      if (quedan > 0 && quedan <= 3 && _ultimoAviso != quedan) {
        _ultimoAviso = quedan;
        _vibrar(_beepTick);
      }
    }

    // For time: una señal cada tantos segundos de lo que lleva.
    final cada = crono.fase.senalCadaSeg;
    final pasados = crono.transcurridos(ahoraMs);
    if (cada != null && pasados > 0 && pasados % cada == 0 && _ultimaSenal != pasados) {
      _ultimaSenal = pasados;
      _vibrar(_beepPhase);
    }

    final segundos = crono.visibles(ahoraMs);
    if (segundos != state!.segundos) _publicar(crono, agendar: false);
  }

  /// El atleta pasó de fase con "Terminar": la siguiente, o cierra si [crono] era la última. Suena en el momento.
  void _avanzar(Crono crono) {
    final siguiente = crono.avanzar(ahora());
    if (siguiente == null) {
      _avisar(_beepEnd);
      detener();
      return;
    }
    _ultimoAviso = null;
    _ultimaSenal = null;
    _avisar(_beepPhase);
    _publicar(siguiente);
  }

  void _cambiar(Crono Function(Crono) cambio) {
    final crono = state?.crono;
    if (crono != null) _publicar(cambio(crono));
  }

  /// Pinta [crono] y, salvo que [agendar] sea falso, reemplaza los sonidos agendados por los que le quedan. Un paso de
  /// fase por tiempo no reagenda: lo que viene ya estaba agendado desde el último cambio.
  void _publicar(Crono crono, {bool agendar = true}) {
    final ahoraMs = ahora();
    state = VistaCrono(crono, crono.visibles(ahoraMs));
    if (!agendar) return;
    final tonos = [
      for (final c in cuesAhead(crono, ahoraMs))
        (at: c.at, hz: _avisoDe(c.cue).hz, duration: _avisoDe(c.cue).duration),
    ];
    _seguro((p) => p.schedule(tonos));
  }

  void _avisar(_Aviso aviso) {
    _seguro((p) => p.beep(hz: aviso.hz, duration: aviso.duration));
    _vibrar(aviso);
  }

  void _vibrar(_Aviso aviso) => _seguro((p) => p.vibrate(aviso.vibrate));

  /// Sound, vibration and screen are best effort: whatever fails, synchronously or not, is ignored.
  void _seguro(Future<void> Function(TimerPlatform) accion) {
    try {
      unawaited(accion(ref.read(timerPlatformProvider)).catchError((Object _) {}));
    } catch (_) {
      // The device does not support it.
    }
  }
}
