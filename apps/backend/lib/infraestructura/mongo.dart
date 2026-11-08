import 'dart:io';

import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Nombres de colecciones, uno por colección, a medida que los features las crean.
/// Cada slice lee y escribe lo que necesita directamente; no hay repositorios compartidos.
/// Todo documento lleva `clubId` (salvo usuarios y sesiones de login) y toda consulta filtra por
/// él; lo de plataforma usa `clubPlataforma` (docs/diseno.md, "Club, usuarios y roles").
abstract final class Colecciones {
  /// One per device a user logged in from (F1). Global: no `clubId`.
  static const loginSessions = 'login_sessions';

  /// Global: no `clubId`. `email` is stored normalized (`normalizarEmail`) and is unique.
  static const usuarios = 'usuarios';
  static const clubes = 'clubes';

  /// One per (`clubId`, `usuarioId`).
  static const membresias = 'membresias';

  /// One per (`clubId`, `usuarioId`).
  static const atletas = 'atletas';

  /// Catalog (F2): base documents have `clubId` = `plataforma`, the club's own its id.
  static const ejercicios = 'ejercicios';
  static const categorias = 'categorias';
  static const temporizadores = 'temporizadores';
  static const gruposMusculares = 'grupos_musculares';
  static const patrones = 'patrones_movimiento';

  /// One per club: `_id` is the `clubId` (F2 S3). A club with no document uses the standard.
  static const equipos = 'equipos';

  /// Athlete references (F3): one document per entry of the history, never overwritten.
  static const referencias = 'referencias';

  /// Work factors (F3): one document per entry of the history, never overwritten.
  static const factoresTrabajo = 'factores_trabajo';

  /// Fixed weights (F3): one document per (`clubId`, `atletaId`, `ejercicioId`), replaced in place.
  static const kilajesFijos = 'kilajes_fijos';

  /// Plans (F5): one document per plan, saved whole (week models, assignment, days, blocks, sets).
  static const planes = 'planes';

  /// WoDs of the club's library (E5.11): reusable groups of prescriptions copied into plan blocks.
  static const wods = 'wods';

  /// Groups of athletes (E6): created by the seeding script, read by the app. One document per group.
  static const grupos = 'grupos';

  /// Assignments of a plan to a group (E6.3): one document per assignment, ended ones are kept.
  static const asignaciones = 'asignaciones';
}

String urlMongoDesdeEntorno() =>
    Platform.environment['MONGO_URL'] ?? 'mongodb://localhost:27017/maktub';

Future<Db> abrirMongo([String? url]) async {
  final db = await Db.create(url ?? urlMongoDesdeEntorno());
  await db.open();
  return db;
}

/// Índices que necesitan los features; idempotente, se corre al arrancar.
Future<void> asegurarIndices(Db db) async {
  // To list and revoke a user's sessions (e.g. "close all my other devices").
  await db
      .collection(Colecciones.loginSessions)
      .createIndex(keys: {'userId': 1}, name: 'userId');
  // Mongo deletes each session on its own once `expiresAt` passes (F1: expired sessions clean themselves up).
  // mongo_dart's createIndex has no expireAfterSeconds option, so use the raw command (idempotent).
  await db.runCommand({
    'createIndexes': Colecciones.loginSessions,
    'indexes': [
      {
        'key': {'expiresAt': 1},
        'name': 'expiresAt_ttl',
        'expireAfterSeconds': 0,
      },
    ],
  });

  await db
      .collection(Colecciones.usuarios)
      .createIndex(keys: {'email': 1}, name: 'email_unico', unique: true);
  await db
      .collection(Colecciones.membresias)
      .createIndex(
        keys: {'clubId': 1, 'usuarioId': 1},
        name: 'club_usuario_unico',
        unique: true,
      );
  await db
      .collection(Colecciones.atletas)
      .createIndex(
        keys: {'clubId': 1, 'usuarioId': 1},
        name: 'club_usuario_unico',
        unique: true,
      );

  // History lookups: the entries of one athlete and exercise, by date.
  for (final name in [Colecciones.referencias, Colecciones.factoresTrabajo]) {
    await db
        .collection(name)
        .createIndex(
          keys: {'clubId': 1, 'atletaId': 1, 'ejercicioId': 1, 'fecha': 1},
          name: 'club_atleta_ejercicio_fecha',
        );
  }

  await db
      .collection(Colecciones.kilajesFijos)
      .createIndex(
        keys: {'clubId': 1, 'atletaId': 1, 'ejercicioId': 1},
        name: 'club_atleta_ejercicio_unico',
        unique: true,
      );

  // Listing the plans of a club.
  await db
      .collection(Colecciones.planes)
      .createIndex(keys: {'clubId': 1, 'nombre': 1}, name: 'club_nombre');

  // Listing the WoDs of a club's library.
  await db.collection(Colecciones.wods).createIndex(keys: {'clubId': 1, 'nombre': 1}, name: 'club_nombre');

  // Listing the groups of a club.
  await db.collection(Colecciones.grupos).createIndex(keys: {'clubId': 1}, name: 'club');

  // Assignments (E6.3): listing by club and group, and the rule "a group has at most one active assignment"
  // (D14). Atomic writes touch one document and the driver has no transactions (D15), so the rule lives in the
  // database: a unique partial index, which only covers the active ones (ended and paused ones may repeat).
  await db
      .collection(Colecciones.asignaciones)
      .createIndex(keys: {'clubId': 1}, name: 'club');
  await db
      .collection(Colecciones.asignaciones)
      .createIndex(
        keys: {'clubId': 1, 'grupoId': 1},
        name: 'club_grupo_activa_unica',
        unique: true,
        partialFilterExpression: {'estado': 'activa'},
      );

  // "In use" checks (E5.4): multikey indexes on the exercise and timer references inside plans.
  const blocks = 'modelosSemana.dias.bloques';
  for (final (name, path) in [
    ('club_uso_ejercicio', '$blocks.prescripciones.ejercicioId'),
    ('club_uso_temporizador_bloque', '$blocks.temporizadorId'),
    ('club_uso_temporizador_prescripcion', '$blocks.prescripciones.temporizadorId'),
  ]) {
    await db.collection(Colecciones.planes).createIndex(keys: {'clubId': 1, path: 1}, name: name);
  }

  // The same checks against the library WoDs: a WoD's exercises and timers also count as usage.
  for (final (name, path) in [
    ('club_uso_ejercicio', 'prescripciones.ejercicioId'),
    ('club_uso_temporizador_wod', 'temporizadorId'),
    ('club_uso_temporizador_prescripcion', 'prescripciones.temporizadorId'),
  ]) {
    await db.collection(Colecciones.wods).createIndex(keys: {'clubId': 1, path: 1}, name: name);
  }
}

/// Documento de Mongo (`_id`) → JSON del dominio (`id`).
Json desdeDocumento(Map<String, dynamic> doc) {
  final copia = Map<String, dynamic>.of(doc);
  final id = copia.remove('_id');
  return {'id': id is ObjectId ? id.oid : id, ...copia};
}

/// JSON del dominio (`id`) → documento de Mongo (`_id`).
Map<String, dynamic> aDocumento(Json json, {String? id}) {
  final copia = Map<String, dynamic>.of(json);
  final propio = copia.remove('id');
  return {'_id': id ?? propio, ...copia};
}
