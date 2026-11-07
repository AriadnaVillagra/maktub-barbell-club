import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../domain/crono.dart';

/// Lo que la barra del temporizador pinta.
class VistaCrono {
  const VistaCrono(this.crono, this.restantes);

  final Crono crono;
  final int restantes;
}

final cronoControllerProvider = NotifierProvider<CronoController, VistaCrono?>(CronoController.new);

/// Avisos con vibración: los últimos 3 segundos, el cambio de fase y el final.
/// Pendiente: sonido y mantener la pantalla encendida.
class CronoController extends Notifier<VistaCrono?> {
  Timer? _tic;
  int? _ultimoAviso;

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
    _publicar(crono);
    _tic = Timer.periodic(const Duration(milliseconds: 200), (_) => _tictac());
    return true;
  }

  void alternarPausa() => _cambiar((c) => c.alternarPausa(ahora()));

  void sumar(int segundos) {
    _ultimoAviso = null;
    _cambiar((c) => c.sumar(segundos, ahora()));
  }

  void detener() {
    _tic?.cancel();
    _tic = null;
    state = null;
  }

  void _tictac() {
    final crono = state?.crono;
    if (crono == null || crono.enPausa) return;
    final quedan = crono.restantes(ahora());

    if (quedan > 0 && quedan <= 3 && _ultimoAviso != quedan) {
      _ultimoAviso = quedan;
      HapticFeedback.selectionClick();
    }
    if (quedan > 0) {
      if (quedan != state!.restantes) _publicar(crono);
      return;
    }

    final siguiente = crono.avanzar(ahora());
    if (siguiente == null) {
      HapticFeedback.heavyImpact();
      detener();
      return;
    }
    _ultimoAviso = null;
    HapticFeedback.mediumImpact();
    _publicar(siguiente);
  }

  void _cambiar(Crono Function(Crono) cambio) {
    final crono = state?.crono;
    if (crono != null) _publicar(cambio(crono));
  }

  void _publicar(Crono crono) => state = VistaCrono(crono, crono.restantes(ahora()));
}
