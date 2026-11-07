import 'dart:io';

import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

Future<bool> _mongoDisponible() async {
  try {
    final socket = await Socket.connect('localhost', 27017, timeout: const Duration(seconds: 1));
    await socket.close();
    return true;
  } on Object {
    return false;
  }
}

void main() {
  late Db db;
  var disponible = false;

  setUpAll(() async {
    disponible = await _mongoDisponible();
    if (!disponible) return;
    db = await abrirMongo('mongodb://localhost:27017/maktub_test_indices');
  });

  tearDownAll(() async {
    if (!disponible) return;
    await db.drop();
    await db.close();
  });

  test('login_sessions has a TTL index on expiresAt, idempotent', () async {
    if (!disponible) {
      markTestSkipped('MongoDB is not reachable on localhost:27017');
      return;
    }
    await asegurarIndices(db);
    await asegurarIndices(db);
    final indices = await db.collection(Colecciones.loginSessions).getIndexes();
    final ttl = indices.where((i) => (i['key'] as Map).containsKey('expiresAt')).toList();
    expect(ttl, hasLength(1));
    expect(ttl.single['expireAfterSeconds'], 0);
    expect(ttl.single['key'], {'expiresAt': 1});
  });
}
