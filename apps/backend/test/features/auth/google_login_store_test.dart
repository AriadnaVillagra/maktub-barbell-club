import 'dart:io';

import 'package:maktub_backend/features/auth/google_login/google_login_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e17_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base = Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
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

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB no disponible');
        return;
      }
      await body();
    });
  }

  mongoTest('finds by email and links the Google sub only once', () async {
    final users = db!.collection(Colecciones.usuarios);
    final objectId = ObjectId();
    await users.insertMany([
      {'_id': 'u-ari', 'email': 'ari@example.com', 'metodos': <String>[], 'emailVerificado': false},
      {'_id': objectId, 'email': 'andi@example.com'},
    ]);
    final store = MongoGoogleLoginStore(db!);

    expect(await store.findByEmail('nadie@example.com'), isNull);
    expect(await store.findByEmail('ari@example.com'), (id: 'u-ari', googleSub: null));
    expect((await store.findByEmail('andi@example.com'))!.id, objectId.oid);

    expect(await store.linkGoogleSub('ari@example.com', 'sub-1'), isTrue);
    expect(await store.linkGoogleSub('ari@example.com', 'sub-2'), isFalse);
    expect(await store.findByEmail('ari@example.com'), (id: 'u-ari', googleSub: 'sub-1'));

    final doc = await users.findOne({'_id': 'u-ari'});
    expect(doc!['metodos'], ['google']);
    expect(doc['emailVerificado'], isTrue);
    expect(await users.count(), 2);
  });
}
