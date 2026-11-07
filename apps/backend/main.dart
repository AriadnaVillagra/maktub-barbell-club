import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

late Db _db;

/// Se ejecuta una sola vez al arrancar (también con hot reload en `dart_frog dev`).
Future<void> init(InternetAddress ip, int port) async {
  _db = await abrirMongo();
  await asegurarIndices(_db);
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) =>
    serve(handler.use(provider<Db>((_) => _db)), ip, port);
