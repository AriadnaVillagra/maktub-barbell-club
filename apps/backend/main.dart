import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/google_id_token.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

late MongoConnection _mongo;
late AccessTokenCodec _tokens;
late GoogleIdTokenVerifier _google;
final _liveTickets = LiveTickets();
final _liveBroadcast = MemoryLiveBroadcast();

/// Se ejecuta una sola vez al arrancar (también con hot reload en `dart_frog dev`).
Future<void> init(InternetAddress ip, int port) async {
  final db = await abrirMongo();
  await asegurarIndices(db);
  _mongo = MongoConnection(db);
  _tokens = AccessTokenCodec.fromEnvironment();
  _google = GoogleIdTokenVerifier.fromEnvironment();
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) => serve(
      handler
          .use(provider<Db>((_) => _mongo.db))
          .use(provider<AccessTokenCodec>((_) => _tokens))
          .use(provider<GoogleIdTokenVerifier>((_) => _google))
          .use(provider<LiveTickets>((_) => _liveTickets))
          .use(provider<LiveBroadcast>((_) => _liveBroadcast))
          .use(_reopenMongoIfDown),
      ip,
      port,
    );

/// Before each request, replaces a dropped Mongo connection (see [MongoConnection]).
Handler _reopenMongoIfDown(Handler handler) => (context) async {
      await _mongo.ensureOpen();
      return handler(context);
    };
