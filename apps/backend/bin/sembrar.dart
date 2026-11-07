/// Carga los catálogos, atletas, RMs y un plan de ejemplo en Mongo.
/// Idempotente: solo inserta lo que falta, nunca pisa datos existentes.
///
///   dart run bin/sembrar.dart            (usa MONGO_URL o mongodb://localhost:27017/maktub)
library;

import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_backend/semilla/datos_iniciales.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

Future<void> main() async {
  final db = await abrirMongo();
  try {
    await asegurarIndices(db);

    Future<void> sembrarPorId(String coleccion, List<Json> docs) async {
      var nuevos = 0;
      for (final d in docs) {
        final existe = await db.collection(coleccion).findOne(where.eq('_id', d['id']));
        if (existe == null) {
          await db.collection(coleccion).insertOne(aDocumento(d));
          nuevos++;
        }
      }
      print('$coleccion: $nuevos nuevos de ${docs.length}');
    }

    await sembrarPorId(Colecciones.ejercicios, [for (final e in catalogoInicial) e.toJson()]);
    await sembrarPorId(Colecciones.temporizadores, [for (final t in temporizadoresIniciales) t.toJson()]);
    await sembrarPorId(Colecciones.wods, [for (final w in wodsIniciales) w.toJson()]);
    await sembrarPorId(Colecciones.atletas, [for (final a in atletasIniciales) a.toJson()..remove('rms')]);

    if (await db.collection(Colecciones.rms).count() == 0) {
      await db.collection(Colecciones.rms).insertMany([
        for (final (atleta, basico, kilos) in rmsIniciales)
          {'atleta': atleta, 'basico': basico.cable, 'kilos': kilos, 'fecha': aIsoFecha(fechaRmsIniciales)},
      ]);
      print('rms: ${rmsIniciales.length} nuevos');
    }

    if (await db.collection(Colecciones.planes).count() == 0) {
      final hoyUtc = hoy();
      final lunes = hoyUtc.subtract(Duration(days: hoyUtc.weekday - DateTime.monday));
      await db.collection(Colecciones.planes).insertOne(aDocumento(planDeEjemplo(lunes).toJson()));
      print('planes: plan de ejemplo creado, empieza el ${aIsoFecha(lunes)}');
    }
  } finally {
    await db.close();
  }
}
