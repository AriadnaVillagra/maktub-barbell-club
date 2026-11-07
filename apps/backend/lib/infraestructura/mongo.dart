import 'dart:io';

import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Nombres de colecciones, uno por colección, a medida que los features las crean.
/// Cada slice lee y escribe lo que necesita directamente; no hay repositorios compartidos.
/// Todo documento lleva `clubId` (salvo usuarios y sesiones de login) y toda consulta filtra por
/// él; lo de plataforma usa `clubPlataforma` (docs/diseno.md, "Club, usuarios y roles").
abstract final class Colecciones {}

String urlMongoDesdeEntorno() =>
    Platform.environment['MONGO_URL'] ?? 'mongodb://localhost:27017/maktub';

Future<Db> abrirMongo([String? url]) async {
  final db = await Db.create(url ?? urlMongoDesdeEntorno());
  await db.open();
  return db;
}

/// Índices que necesitan los features; idempotente, se corre al arrancar.
Future<void> asegurarIndices(Db db) async {}

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
