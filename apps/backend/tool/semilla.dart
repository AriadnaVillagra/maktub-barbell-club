// Idempotent seed of the base catalog (design.md 3.5): `cd apps/backend && dart run tool/semilla.dart`.
//
// Loads tool/semilla/catalogo_base.json (the list approved in E2.6) into `plataforma`. Only inserts
// what is missing; never overwrites. It writes to MONGO_URL.
import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/catalogo/seed/seed.dart';
import 'package:maktub_backend/features/catalogo/seed/seed_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';

Future<void> main() async {
  final archivo = File(Platform.environment['SEMILLA_ARCHIVO'] ?? 'tool/semilla/catalogo_base.json');
  final catalogo = BaseCatalog.fromJson(
    jsonDecode(archivo.readAsStringSync()) as Map<String, dynamic>,
    now: DateTime.now(),
  );
  final db = await abrirMongo();
  try {
    stdout.writeln('Base: ${db.databaseName}');
    final r = await BaseSeed(MongoSeedStore(db)).run(catalogo);
    for (final c in r.created) {
      stdout.writeln('creado:   $c');
    }
    for (final e in r.existing) {
      stdout.writeln('ya estaba: $e');
    }
    for (final d in r.differing) {
      stdout.writeln('DIFIERE de la lista (no se tocó): $d');
    }
    stdout.writeln(
      'Resumen: ${r.created.length} creados, ${r.existing.length} ya estaban, '
      '${r.differing.length} difieren.',
    );
  } finally {
    await db.close();
  }
}
