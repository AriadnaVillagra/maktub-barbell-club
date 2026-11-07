import 'dart:io';

import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e14_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base =
          Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
      await asegurarIndices(db!);
    } on Object catch (e) {
      stderr.writeln('mongo: $e');
      db = null;
    }
  });

  tearDownAll(() async {
    await db?.drop();
    await db?.close();
  });

  Future<void> expectDuplicate(
    String coleccion,
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) async {
    final c = db!.collection(coleccion);
    await c.insertOne({'_id': 'a', ...a});
    final result = await c.insertOne({'_id': 'b', ...b});
    expect(result.isSuccess, isFalse);
    expect(result.writeError?.code, 11000); // duplicate key
    expect(await c.count(), 1);
  }

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB no disponible');
        return;
      }
      await body();
    });
  }

  mongoTest('asegurarIndices es idempotente', () async {
    await asegurarIndices(db!);
    await asegurarIndices(db!);
  });

  mongoTest('el email de usuarios es único', () async {
    await expectDuplicate(
      Colecciones.usuarios,
      {'email': 'a@x.com'},
      {'email': 'a@x.com'},
    );
  });

  mongoTest('la membresía es única por club y usuario', () async {
    await expectDuplicate(
      Colecciones.membresias,
      {'clubId': 'c1', 'usuarioId': 'u1'},
      {'clubId': 'c1', 'usuarioId': 'u1'},
    );
    await db!.collection(Colecciones.membresias).insertOne({
      '_id': 'c',
      'clubId': 'c2',
      'usuarioId': 'u1',
    });
  });

  mongoTest('el atleta es único por club y usuario', () async {
    await expectDuplicate(
      Colecciones.atletas,
      {'clubId': 'c1', 'usuarioId': 'u1'},
      {'clubId': 'c1', 'usuarioId': 'u1'},
    );
    await db!.collection(Colecciones.atletas).insertOne({
      '_id': 'c',
      'clubId': 'c2',
      'usuarioId': 'u1',
    });
  });
}
