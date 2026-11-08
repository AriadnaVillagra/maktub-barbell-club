// One-off data changes after the E2 review: `cd apps/backend && dart run tool/ajustes_e2.dart`.
//
// Idempotent. It writes to MONGO_URL:
// - removes the seeded notes text from the default exercises;
// - gives `admin_club` to every coach of a real (non-personal) club;
// - marks the users in ADMIN_PLATAFORMA (comma-separated emails, never in the repo) as platform admins.
import 'dart:io';

import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';

Future<void> main() async {
  final db = await abrirMongo();
  try {
    stdout.writeln('Base: ${db.databaseName}');
    final notes = await db.collection(Colecciones.ejercicios).updateMany(
      {'clubId': clubPlataforma, 'notas': {r'$exists': true}},
      {r'$unset': {'notas': ''}},
    );
    stdout.writeln('notas borradas: ${notes.nModified}');

    final clubs = await db.collection(Colecciones.clubes).find({'tipo': TipoClub.club.cable}).toList();
    final memberships = await db.collection(Colecciones.membresias).updateMany(
      {
        'clubId': {r'$in': [for (final c in clubs) c['_id']]},
        'roles': Rol.coach.cable,
      },
      {r'$addToSet': {'roles': Rol.adminClub.cable}},
    );
    stdout.writeln('coaches con admin de club: ${memberships.nModified}');

    final emails = (Platform.environment['ADMIN_PLATAFORMA'] ?? '')
        .split(',')
        .map((e) => normalizarEmail(e))
        .where((e) => e.isNotEmpty)
        .toList();
    if (emails.isEmpty) {
      stdout.writeln('ADMIN_PLATAFORMA vacío: no se marcó ningún administrador de plataforma.');
    } else {
      final admins = await db.collection(Colecciones.usuarios).updateMany(
        {'email': {r'$in': emails}},
        {r'$set': {'esAdminPlataforma': true}},
      );
      stdout.writeln('administradores de plataforma: ${admins.nMatched} de ${emails.length}');
    }
  } finally {
    await db.close();
  }
}
