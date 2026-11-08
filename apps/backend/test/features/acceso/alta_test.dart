import 'dart:io';

import 'package:maktub_backend/features/acceso/alta/alta.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e19_${DateTime.now().microsecondsSinceEpoch}';
  const usuarios = [
    UsuarioAlta(email: 'Andi@Ejemplo.com ', nombre: 'Andi'),
    UsuarioAlta(email: 'ari@ejemplo.com', nombre: 'Ari'),
  ];

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

  Future<Map<String, List<Map<String, dynamic>>>> snapshot() async => {
    for (final c in [
      Colecciones.usuarios,
      Colecciones.clubes,
      Colecciones.membresias,
      Colecciones.atletas,
    ])
      c: await db!.collection(c).find().toList(),
  };

  test('creates clubs, users, memberships and athletes; second run changes nothing', () async {
    if (db == null) {
      markTestSkipped('No local MongoDB');
      return;
    }
    final alta = AltaInicial(db!);
    final primera = await alta.ejecutar(usuarios);
    expect(primera.existentes, isEmpty);
    final antes = await snapshot();

    expect(antes[Colecciones.usuarios], hasLength(2));
    expect(antes[Colecciones.clubes], hasLength(3));
    expect(antes[Colecciones.membresias], hasLength(4));
    expect(antes[Colecciones.atletas], hasLength(4));

    final clubes = {
      for (final c in antes[Colecciones.clubes]!) '${c['_id']}': Club.fromJson(desdeDocumento(c)),
    };
    expect(clubes.values.where((c) => c.tipo == TipoClub.club).map((c) => c.nombre), ['Maktub']);
    for (final doc in antes[Colecciones.usuarios]!) {
      final u = Usuario.fromJson(desdeDocumento(doc));
      expect(u.email, u.email.toLowerCase().trim());
      expect(clubes[u.clubPersonalId]?.tipo, TipoClub.personal);
      final ms = antes[Colecciones.membresias]!.where((m) => m['usuarioId'] == u.id);
      expect(ms, hasLength(2));
      for (final m in ms) {
        final membresia = Membresia.fromJson(desdeDocumento(m));
        // Club admin only in Maktub: a personal club has no one to administer.
        final isMaktub = clubes[membresia.clubId]?.tipo == TipoClub.club;
        expect(membresia.roles, {Rol.coach, Rol.atleta, if (isMaktub) Rol.adminClub});
        expect(membresia.esCoachActivo, isTrue);
      }
    }

    final segunda = await alta.ejecutar(usuarios);
    expect(segunda.creados, isEmpty);
    expect(await snapshot(), antes);
  });
}
