import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../domain/entities/sesion_del_dia.dart';
import '../providers.dart';
import 'estado_seguimiento.dart';

final seguimientoControllerProvider =
    AsyncNotifierProvider<SeguimientoController, EstadoSeguimiento>(SeguimientoController.new);

class SeguimientoController extends AsyncNotifier<EstadoSeguimiento> {
  @override
  Future<EstadoSeguimiento> build() async => _inicial(await ref.read(obtenerSeguimientoProvider)());

  SeguimientoListo? get _listo => switch (state.value) {
        final SeguimientoListo s => s,
        _ => null,
      };

  Equipo get _equipo => ref.read(equipoProvider);

  // ---------- navegación ----------

  void elegirAtleta(String id) => _navegar((s) => s.copyWith(atletaId: id));

  void elegirSemana(int semana) => _navegar((s) {
        final conSemana = s.copyWith(semana: semana);
        return conSemana.copyWith(dia: _primerDiaPendiente(conSemana));
      });

  void elegirDia(int dia) => _navegar((s) => s.copyWith(dia: dia));

  /// La fecha decide ciclo y semana.
  void cambiarFecha(DateTime fecha) {
    final s = _listo;
    if (s == null) return;
    final ubicacion = UbicacionEnCiclo.desdeFechas(inicio: s.plan.inicio, fecha: fecha);
    _emitir(s.copyWith(fecha: soloFecha(fecha), ciclo: ubicacion.ciclo, semana: ubicacion.semana));
  }

  // ---------- edición de la sesión ----------

  void cambiarAjuste(int delta) => _editar((x) => x.cambiarAjuste(delta));

  void cambiarAjusteItem(int item, int delta) => _editar((x) => x.cambiarAjusteItem(item, delta));

  void editarPeso(int item, int serie, double? kg) =>
      _editar((x) => x.editarSerie(item, serie, _equipo, pesoKg: kg, borrarPeso: kg == null));

  void editarReps(int item, int serie, int? reps) =>
      _editar((x) => x.editarSerie(item, serie, _equipo, reps: reps, borrarReps: reps == null));

  void alternarHecha(int item, int serie) => _editar((x) => x.alternarHecha(item, serie));

  void editarNota(int item, String nota) => _editar((x) => x.editarNota(item, nota));

  void restaurar(int item) => _editar((x) => x.restaurar(item));

  // ---------- persistencia ----------

  /// Lanza el error si falla, para que la vista lo muestre; el borrador no se pierde.
  Future<void> guardar() async {
    final s = _listo;
    if (s == null || s.guardando) return;
    _emitir(s.copyWith(guardando: true));
    try {
      final guardada = await ref.read(guardarSesionProvider)(s.sesion, planId: s.plan.id, fecha: s.fecha, equipo: _equipo);
      final actual = _listo ?? s;
      _emitir(actual.copyWith(
        datos: actual.datos.conSesion(guardada),
        borradores: {...actual.borradores}..remove(s.claveActual),
        guardando: false,
      ));
    } catch (_) {
      final actual = _listo;
      if (actual != null) _emitir(actual.copyWith(guardando: false));
      rethrow;
    }
  }

  /// Trae los datos de nuevo y descarta los borradores, conservando atleta y día si siguen existiendo.
  Future<void> refrescar() async {
    final previo = _listo;
    final datos = await ref.read(obtenerSeguimientoProvider)();
    final nuevo = _inicial(datos, atletaPreferido: previo?.atletaId);
    if (previo != null && nuevo is SeguimientoListo && nuevo.plan.numerosDeDia.contains(previo.dia)) {
      state = AsyncData(_conBorrador(_conFechaDelDia(nuevo.copyWith(
        fecha: previo.fecha,
        ciclo: previo.ciclo,
        semana: previo.semana,
        dia: previo.dia,
        borradores: const {},
      ))));
    } else {
      state = AsyncData(nuevo);
    }
  }

  // ---------- internos ----------

  EstadoSeguimiento _inicial(SeguimientoSnapshot datos, {String? atletaPreferido}) {
    final plan = datos.plan;
    if (plan == null) {
      return const SeguimientoNoDisponible('No hay un plan activo.\nCreá uno o marcá uno como activo.');
    }
    if (datos.atletas.isEmpty) return const SeguimientoNoDisponible('No hay atletas cargados.');
    if (plan.numerosDeDia.isEmpty) return const SeguimientoNoDisponible('El plan activo no tiene días.');

    final fecha = ref.read(hoyProvider)();
    final ubicacion = UbicacionEnCiclo.desdeFechas(inicio: plan.inicio, fecha: fecha);
    final atletaId = datos.atletas.any((a) => a.id == atletaPreferido) ? atletaPreferido! : datos.atletas.first.id;
    final base = SeguimientoListo(
      datos: datos,
      atletaId: atletaId,
      fecha: fecha,
      ciclo: ubicacion.ciclo,
      semana: ubicacion.semana,
      dia: plan.numerosDeDia.first,
    );
    return _conBorrador(_conFechaDelDia(base.copyWith(dia: _primerDiaPendiente(base))));
  }

  int _primerDiaPendiente(SeguimientoListo s) {
    final dias = s.plan.numerosDeDia;
    return dias.where((d) => !s.diaRegistrado(s.semana, d)).firstOrNull ?? dias.first;
  }

  /// Un día ya registrado muestra su propia fecha; uno pendiente, la de hoy.
  SeguimientoListo _conFechaDelDia(SeguimientoListo s) {
    final registrada = s.datos.sesiones
        .where((x) => x.clave == SesionRegistrada.claveSesion(atleta: s.atletaId, plan: s.plan.id, ciclo: s.ciclo, semana: s.semana, dia: s.dia))
        .firstOrNull;
    return s.copyWith(fecha: registrada?.fecha ?? ref.read(hoyProvider)());
  }

  SeguimientoListo _conBorrador(SeguimientoListo s) {
    if (s.borradores.containsKey(s.claveActual)) return s;
    final sesion = ref.read(construirSesionProvider)(s.datos, atletaId: s.atletaId, ciclo: s.ciclo, semana: s.semana, dia: s.dia);
    return s.copyWith(borradores: {...s.borradores, s.claveActual: sesion});
  }

  void _emitir(SeguimientoListo s) => state = AsyncData(_conBorrador(s));

  void _navegar(SeguimientoListo Function(SeguimientoListo) cambio) {
    final s = _listo;
    if (s != null) _emitir(_conFechaDelDia(cambio(s)));
  }

  void _editar(SesionDelDia Function(SesionDelDia) cambio) {
    final s = _listo;
    if (s == null) return;
    _emitir(s.copyWith(borradores: {...s.borradores, s.claveActual: cambio(s.sesion)}));
  }
}
