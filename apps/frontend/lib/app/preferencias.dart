import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Tema que fijó el usuario. Por defecto `sistema`: entrenamiento en oscuro, el resto
/// según el sistema. Pendiente: persistirlo (pantalla de ajustes).
final preferenciaTemaProvider = NotifierProvider<PreferenciaTemaController, PreferenciaTema>(PreferenciaTemaController.new);

class PreferenciaTemaController extends Notifier<PreferenciaTema> {
  @override
  PreferenciaTema build() => PreferenciaTema.sistema;

  void fijar(PreferenciaTema preferencia) => state = preferencia;
}
