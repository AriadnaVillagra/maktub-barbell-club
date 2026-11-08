/// Dominio compartido de Maktub Barbell Club: reglas de entrenamiento puras y los
/// modelos que frontend y backend intercambian. Sin dependencias ni I/O.
///
/// Los modelos de cada feature (clubes, catálogo, referencias, planes, sesiones...)
/// se agregan acá a medida que se construyen, siguiendo "Modelo del dominio" en docs/diseno.md.
library;

export 'src/modelos/asignacion.dart';
export 'src/modelos/base.dart';
export 'src/modelos/cable.dart';
export 'src/modelos/catalogo.dart';
export 'src/modelos/clubes.dart';
export 'src/modelos/grupo.dart';
export 'src/modelos/json.dart' show Json;
export 'src/modelos/plan.dart';
export 'src/modelos/referencias.dart';
export 'src/modelos/sesion.dart';
export 'src/modelos/temporizador.dart';
export 'src/modelos/usuario.dart';
export 'src/modelos/wod.dart';
export 'src/models/issued_session.dart';
export 'src/reglas/catalogo.dart';
export 'src/reglas/daily_adjustment.dart';
export 'src/reglas/ciclo.dart';
export 'src/reglas/equipo.dart';
export 'src/reglas/fases.dart';
export 'src/reglas/fechas.dart';
export 'src/reglas/load_source.dart';
export 'src/reglas/permisos.dart';
export 'src/reglas/plan_validation.dart';
export 'src/reglas/ramp.dart';
export 'src/reglas/set_load.dart';
export 'src/reglas/porcentajes.dart';
export 'src/reglas/vigencia.dart';
export 'src/reglas/wod_validation.dart';
