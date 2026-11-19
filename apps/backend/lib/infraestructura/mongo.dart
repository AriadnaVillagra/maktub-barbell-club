import 'dart:async';
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

  /// The timers each user keeps at hand in a club (QuickTimers): `_id` is `<clubId>:<usuarioId>`.
  static const temporizadoresAMano = 'temporizadores_a_mano';
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

  /// Sessions (E7.3): one per (`clubId`, `asignacionId`, `fecha`, `semana`, `dia`).
  static const sesiones = 'sesiones';

  /// Per-set records (E7.3): one per (`clubId`, `sesionId`, `atletaId`, `bloque`, `prescripcion`, `serie`).
  static const registros = 'registros';

  /// Block times (E7.19): one per client-generated id, read by session (`clubId`, `sesionId`).
  static const tiemposBloque = 'tiempos_bloque';
}

String urlMongoDesdeEntorno() =>
    Platform.environment['MONGO_URL'] ?? 'mongodb://localhost:27017/maktub';

Future<Db> abrirMongo([String? url]) async {
  final db = await Db.create(withSafeAtlas(url ?? urlMongoDesdeEntorno()));
  await db.open();
  return db;
}

/// Adds `safeAtlas=true` unless the URL already sets it. Without it, Atlas resets the socket when
/// several queries are in flight at once (seen in production on 2026-11-15 with the week's
/// `ubicacion` requests), and mongo_dart then fails every query until the process restarts.
/// With it, mongo_dart sends one query at a time per connection.
String withSafeAtlas(String url) {
  final uri = Uri.parse(url);
  if (uri.queryParameters.containsKey('safeAtlas')) return url;
  return uri.replace(queryParameters: {...uri.queryParameters, 'safeAtlas': 'true'}).toString();
}

/// Keeps one open connection and opens a new one when the current one dropped, so a reset from
/// the server costs the requests in flight, not every request until the instance restarts.
class MongoConnection {
  MongoConnection(this._db, {Future<Db> Function()? open}) : _open = open ?? abrirMongo;

  Db _db;
  final Future<Db> Function() _open;
  Future<void>? _reopening;

  /// The current connection. Read it per request, after [ensureOpen].
  Db get db => _db;

  /// Opens a new connection when the current one is down. Concurrent callers share one attempt;
  /// when it fails they all get the error and the next call tries again.
  Future<void> ensureOpen() {
    if (_db.isConnected) return Future.value();
    return _reopening ??= _reopen().whenComplete(() => _reopening = null);
  }

  Future<void> _reopen() async {
    final old = _db;
    _db = await _open();
    unawaited(old.close().catchError((Object _) {}));
  }
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

  // Assignments (E6.3, E6.7): listing by club, and the active ones an athlete is in. E6.7 drops D14 (an athlete
  // may be in any number of active assignments), so the unique indexes that enforced it go, and the assignments
  // written before E6.7 get their list of athletes (`atletas`) copied from their group or athlete.
  final assignments = db.collection(Colecciones.asignaciones);
  await assignments.createIndex(keys: {'clubId': 1}, name: 'club');
  for (final name in ['club_grupo_activa_unica', 'club_atleta_activa_unica']) {
    await _dropIndexIfExists(assignments, name);
  }
  await assignments.createIndex(
    keys: {'clubId': 1, 'atletas.atletaId': 1, 'estado': 1},
    name: 'club_atleta_estado',
  );
  await copyAssignmentAthletes(db);

  // "In use" checks (E5.4): multikey indexes on the exercise and timer references inside plans.
  const blocks = 'modelosSemana.dias.bloques';
  for (final (name, path) in [
    ('club_uso_ejercicio', '$blocks.prescripciones.ejercicioId'),
    ('club_uso_temporizador_bloque', '$blocks.temporizadorId'),
    ('club_uso_temporizador_prescripcion', '$blocks.prescripciones.temporizadorId'),
    ('club_uso_publicado_ejercicio', 'publicado.$blocks.prescripciones.ejercicioId'),
    ('club_uso_publicado_temporizador_bloque', 'publicado.$blocks.temporizadorId'),
    ('club_uso_publicado_temporizador_prescripcion', 'publicado.$blocks.prescripciones.temporizadorId'),
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

  // The keys of the atomic upserts of a session and of a set record (D15, diseno "Multi-dispositivo").
  await db
      .collection(Colecciones.sesiones)
      .createIndex(
        keys: {'clubId': 1, 'asignacionId': 1, 'fecha': 1, 'semana': 1, 'dia': 1},
        name: 'club_asignacion_fecha_semana_dia_unico',
        unique: true,
      );
  await db
      .collection(Colecciones.registros)
      .createIndex(
        keys: {
          'clubId': 1,
          'sesionId': 1,
          'atletaId': 1,
          'bloque': 1,
          'prescripcion': 1,
          'serie': 1,
        },
        name: 'club_sesion_atleta_posicion_unico',
        unique: true,
      );

  // Reading the block times of a session (E7.19). The document id is the client's, so it is already unique.
  await db.collection(Colecciones.tiemposBloque).createIndex(keys: {'clubId': 1, 'sesionId': 1}, name: 'club_sesion');
}

/// Atomically applies [update] to the document [filter] matches, inserting it if there is none, and returns the
/// document as it ended up. [filter] must be exactly the fields of a unique index: under concurrency one of the
/// inserts can lose the race with a duplicate key error, and retrying then finds and updates the winner's
/// document, so no write is lost and the key never repeats.
Future<Map<String, dynamic>> upsertByUniqueKey(
  DbCollection collection,
  Map<String, dynamic> filter,
  Map<String, dynamic> update,
) async {
  const attempts = 5;
  for (var attempt = 1; ; attempt++) {
    final result = await collection.modernFindAndModify(
      query: filter,
      update: update,
      upsert: true,
      returnNew: true,
    );
    final doc = result.value;
    if (result.success && doc != null) return doc;
    if (result.code != _duplicateKey || attempt == attempts) {
      throw StateError('Upsert failed on ${collection.collectionName}: ${result.errmsg}');
    }
  }
}

const _duplicateKey = 11000;

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

/// Drops the index [name] of [collection] when its partial filter does not mention [field]: an index from before
/// that filter existed, which `createIndex` cannot change in place (same name, other options). Nothing happens if
/// there is no such index or it already has the field.
Future<void> _dropIndexIfExists(DbCollection collection, String name) async {
  for (final index in await collection.getIndexes()) {
    if (index['name'] == name) {
      await collection.dropIndexes(name);
      return;
    }
  }
}

/// E6.7: gives every assignment written before E6.7 its list of athletes, from its owner then: an athlete's own
/// (`atletaId`) is that athlete, a group's (`grupoId`) is the group's members now; each in from the start date.
/// `atletaId` is removed and `grupoId` kept (it says which group the list came from). Idempotent: it only touches
/// documents without `atletas`.
Future<void> copyAssignmentAthletes(Db db) async {
  final assignments = db.collection(Colecciones.asignaciones);
  final legacy = await assignments.find({
    'atletas': {r'$exists': false},
  }).toList();
  for (final doc in legacy) {
    final start = '${doc['fechaInicio']}';
    final List<String> athletes;
    if (doc['atletaId'] != null) {
      athletes = ['${doc['atletaId']}'];
    } else if (doc['grupoId'] != null) {
      final group = await db.collection(Colecciones.grupos).findOne({
        '_id': doc['grupoId'],
        'clubId': doc['clubId'],
      });
      athletes = [
        for (final m in (group?['miembros'] as List? ?? const [])) '$m',
      ];
    } else {
      athletes = const [];
    }
    await assignments.updateOne(
      {
        '_id': doc['_id'],
        'atletas': {r'$exists': false},
      },
      {
        r'$set': {
          'atletas': [
            for (final a in athletes) {'atletaId': a, 'desde': start},
          ],
        },
        r'$unset': {'atletaId': ''},
      },
    );
  }
}
