// Idempotent seed script (design.md 3.5): `cd apps/backend && dart run tool/alta.dart`.
//
// Users come from the ALTA_USUARIOS env var ("email:Nombre,email:Nombre") or, if unset, from the
// JSON file in ALTA_ARCHIVO (default `tool/alta.local.json`, ignored by git; see
// `tool/alta.ejemplo.json`). Real emails never go into the repo. It writes to MONGO_URL.
import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/acceso/alta/alta.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';

List<UsuarioAlta> _leerUsuarios() {
  final env = Platform.environment;
  final inline = env['ALTA_USUARIOS'];
  if (inline != null && inline.trim().isNotEmpty) {
    return [
      for (final par in inline.split(',').where((p) => p.trim().isNotEmpty))
        _desdePar(par),
    ];
  }
  final archivo = File(env['ALTA_ARCHIVO'] ?? 'tool/alta.local.json');
  if (!archivo.existsSync()) {
    throw StateError(
      'Falta la configuración: definí ALTA_USUARIOS="email:Nombre,..." o creá ${archivo.path} '
      '(ver tool/alta.ejemplo.json).',
    );
  }
  final lista = (jsonDecode(archivo.readAsStringSync()) as Map)['usuarios'] as List;
  return [
    for (final u in lista)
      UsuarioAlta(email: '${(u as Map)['email']}', nombre: '${u['nombre']}'),
  ];
}

UsuarioAlta _desdePar(String par) {
  final i = par.indexOf(':');
  if (i <= 0 || i == par.length - 1) {
    throw FormatException('Esperaba "email:Nombre", recibí "$par".');
  }
  return UsuarioAlta(email: par.substring(0, i).trim(), nombre: par.substring(i + 1).trim());
}

Future<void> main() async {
  final usuarios = _leerUsuarios();
  final db = await abrirMongo();
  try {
    stdout.writeln('Base: ${db.databaseName}');
    final r = await AltaInicial(db).ejecutar(usuarios);
    for (final c in r.creados) {
      stdout.writeln('creado:   $c');
    }
    for (final e in r.existentes) {
      stdout.writeln('ya estaba: $e');
    }
  } finally {
    await db.close();
  }
}
