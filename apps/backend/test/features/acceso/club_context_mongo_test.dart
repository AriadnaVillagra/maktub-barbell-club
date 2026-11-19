import 'dart:io';

import 'package:maktub_backend/features/acceso/club_context/club_context_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// The membership, the club's type and the platform admin flag come in one round trip (2026-11-19).
void main() {
  Db? db;
  final name = 'maktub_test_ctx_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base = Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
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
        markTestSkipped('MongoDB not available');
        return;
      }
      await body();
    });
  }

  final audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 19));

  Future<void> seed() async {
    for (final c in [Colecciones.membresias, Colecciones.clubes, Colecciones.usuarios]) {
      await db!.collection(c).remove({});
    }
    await db!.collection(Colecciones.clubes).insertMany([
      aDocumento(Club(id: 'c1', nombre: 'Maktub', tipo: TipoClub.club, auditoria: audit).toJson()),
      aDocumento(Club(id: 'p1', nombre: 'Mío', tipo: TipoClub.personal, auditoria: audit).toJson()),
    ]);
    await db!.collection(Colecciones.usuarios).insertMany([
      {'_id': 'u1', 'email': 'a@x', 'esAdminPlataforma': true},
      {'_id': 'u2', 'email': 'b@x'},
    ]);
    Map<String, dynamic> membership(String id, String club, String user, EstadoMembresia state) => aDocumento(
      Membresia(
        id: id,
        clubId: club,
        usuarioId: user,
        roles: const {Rol.coach},
        estado: state,
        desde: DateTime.utc(2026, 11),
        auditoria: audit,
      ).toJson(),
    );
    await db!.collection(Colecciones.membresias).insertMany([
      membership('m1', 'c1', 'u1', EstadoMembresia.activa),
      membership('m2', 'p1', 'u2', EstadoMembresia.activa),
      membership('m3', 'c1', 'u2', EstadoMembresia.terminada),
    ]);
  }

  mongoTest('brings the club type and the admin flag with the membership', () async {
    await seed();
    final store = MongoClubContextStore(db!);

    final m = await store.activeMembership(clubId: 'c1', userId: 'u1');

    expect(m?.id, 'm1');
    expect(m?.roles, {Rol.coach});
    expect(await store.clubType('c1'), TipoClub.club);
    expect(await store.isPlatformAdmin('u1'), isTrue);
  });

  mongoTest('another user and club: their own type and flag', () async {
    await seed();
    final store = MongoClubContextStore(db!);

    await store.activeMembership(clubId: 'p1', userId: 'u2');

    expect(await store.clubType('p1'), TipoClub.personal);
    expect(await store.isPlatformAdmin('u2'), isFalse);
  });

  mongoTest('an ended membership, or none, is null; the other answers still query', () async {
    await seed();
    final store = MongoClubContextStore(db!);

    expect(await store.activeMembership(clubId: 'c1', userId: 'u2'), isNull);
    expect(await store.activeMembership(clubId: 'zz', userId: 'u1'), isNull);
    expect(await store.clubType('c1'), TipoClub.club);
    expect(await store.isPlatformAdmin('u1'), isTrue);
  });
}
