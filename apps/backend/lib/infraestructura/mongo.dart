import 'dart:io';

import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Nombres de colecciones. Cada slice lee y escribe lo que necesita directamente;
/// no hay repositorios compartidos entre slices.
abstract final class Colecciones {
  static const atletas = 'atletas';
  static const rms = 'rms';
  static const ejercicios = 'ejercicios';
  static const temporizadores = 'temporizadores';
  static const wods = 'wods';
  static const planes = 'planes';
  static const sesiones = 'sesiones';
}

String urlMongoDesdeEntorno() =>
    Platform.environment['MONGO_URL'] ?? 'mongodb://localhost:27017/maktub';

Future<Db> abrirMongo([String? url]) async {
  final db = await Db.create(url ?? urlMongoDesdeEntorno());
  await db.open();
  return db;
}

Future<void> asegurarIndices(Db db) async {
  await db.createIndex(Colecciones.rms, keys: {'atleta': 1, 'basico': 1, 'fecha': -1});
  await db.createIndex(Colecciones.sesiones, keys: {'plan': 1, 'atleta': 1});
  await db.createIndex(Colecciones.planes, keys: {'activo': 1});
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
