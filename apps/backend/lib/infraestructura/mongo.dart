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
  await db.collection(Colecciones.loginSessions).createIndex(keys: {'userId': 1}, name: 'userId');
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
