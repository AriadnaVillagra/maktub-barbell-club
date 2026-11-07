import 'catalogo.dart';
import 'json.dart';
import 'plan.dart';
import 'sesion_registrada.dart';

/// Todo lo que la vista de seguimiento necesita, en una sola respuesta de `GET /seguimiento`.
class SeguimientoSnapshot {
  const SeguimientoSnapshot({
    this.atletas = const [],
    this.ejercicios = const {},
    this.temporizadores = const {},
    this.wods = const {},
    this.plan,
    this.sesiones = const [],
  });

  final List<Atleta> atletas;
  final Map<String, Ejercicio> ejercicios;
  final Map<String, Temporizador> temporizadores;
  final Map<String, Wod> wods;

  /// El plan activo, si hay uno.
  final Plan? plan;

  /// Sesiones registradas del plan activo.
  final List<SesionRegistrada> sesiones;

  SeguimientoSnapshot conSesion(SesionRegistrada sesion) => SeguimientoSnapshot(
        atletas: atletas,
        ejercicios: ejercicios,
        temporizadores: temporizadores,
        wods: wods,
        plan: plan,
        sesiones: [
          for (final s in sesiones)
            if (s.clave != sesion.clave) s,
          sesion,
        ],
      );

  factory SeguimientoSnapshot.fromJson(Json j) => SeguimientoSnapshot(
        atletas: [for (final a in listaJson(j['atletas'])) Atleta.fromJson(a)],
        ejercicios: {
          for (final e in listaJson(j['ejercicios'])) '${e['id']}': Ejercicio.fromJson(e),
        },
        temporizadores: {
          for (final t in listaJson(j['temporizadores'])) '${t['id']}': Temporizador.fromJson(t),
        },
        wods: {for (final w in listaJson(j['wods'])) '${w['id']}': Wod.fromJson(w)},
        plan: j['plan'] == null ? null : Plan.fromJson((j['plan'] as Map).cast()),
        sesiones: [for (final s in listaJson(j['sesiones'])) SesionRegistrada.fromJson(s)],
      );

  Json toJson() => {
        'atletas': [for (final a in atletas) a.toJson()],
        'ejercicios': [for (final e in ejercicios.values) e.toJson()],
        'temporizadores': [for (final t in temporizadores.values) t.toJson()],
        'wods': [for (final w in wods.values) w.toJson()],
        'plan': plan?.toJson(),
        'sesiones': [for (final s in sesiones) s.toJson()],
      };
}
