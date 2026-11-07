import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/catalogo/data/http_catalog_admin_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_admin_repository.dart';

void main() {
  final audit = Auditoria(
    creadoPor: 'u1',
    creadoEn: DateTime.utc(2026, 11, 7),
  ).toJson();
  final requests = <(String, String, Object?)>[];
  String show((String, String, Object?) r) =>
      '${r.$1} ${r.$2} ${jsonEncode(r.$3)}';

  HttpCatalogAdminRepository repo(
    Map<String, dynamic> Function(http.Request) answer,
  ) {
    requests.clear();
    return HttpCatalogAdminRepository(
      ClienteApi(
        base: Uri.parse('http://api.test'),
        cliente: MockClient((req) async {
          requests.add((
            req.method,
            req.url.path,
            req.body.isEmpty ? null : jsonDecode(req.body),
          ));
          return http.Response(
            jsonEncode(answer(req)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  }

  test('category writes use the verbs of the API', () async {
    final r = repo(
      (req) => req.method == 'DELETE'
          ? {'resultado': 'archivado'}
          : {
              'id': 'k1',
              'clubId': 'c1',
              'nombre': 'Fuerza',
              'auditoria': audit,
            },
    );
    await r.createCategory('c1', 'Fuerza');
    await r.renameCategory('c1', 'k1', 'Fuerza 2');
    await r.setCategoryStatus('c1', 'k1', CatalogStatus.archived);
    expect(await r.deleteCategory('c1', 'k1'), RemovalOutcome.archived);
    expect(requests.map(show), [
      'POST /clubes/c1/catalogo/categorias {"nombre":"Fuerza"}',
      'PUT /clubes/c1/catalogo/categorias/k1 {"nombre":"Fuerza 2"}',
      'PATCH /clubes/c1/catalogo/categorias/k1 {"estado":"archivado"}',
      'DELETE /clubes/c1/catalogo/categorias/k1 null',
    ]);
  });

  test('timer calls hit the timer endpoints', () async {
    final json = {
      'id': 't1',
      'clubId': 'c1',
      'nombre': 'EMOM',
      'tipo': 'emom',
      'trabajoSeg': 60,
      'rondas': 10,
      'estado': 'activo',
      'auditoria': audit,
    };
    final r = repo(
      (req) => req.method == 'GET'
          ? {
              'temporizadores': [json],
            }
          : json,
    );
    expect((await r.timers('c1')).single.nombre, 'EMOM');
    final t = Temporizador.fromJson(json);
    await r.createTimer('c1', t);
    await r.updateTimer('c1', t.copyWith(estado: CatalogStatus.archived));
    await r.archiveTimer('c1', 't1');
    expect(requests.map((e) => (e.$1, e.$2)), [
      ('GET', '/clubes/c1/catalogo/temporizadores'),
      ('POST', '/clubes/c1/temporizadores'),
      ('PUT', '/clubes/c1/temporizadores/t1'),
      ('POST', '/clubes/c1/temporizadores/t1/archivar'),
    ]);
    expect((requests[2].$3! as Map)['estado'], 'archivado');
    expect((requests[1].$3! as Map).containsKey('id'), isFalse);
  });

  test('equipment is read and saved with bar and plates only', () async {
    final r = repo(
      (_) => {
        'clubId': 'c1',
        'barraKg': 15,
        'paresDiscos': [10, 5],
        'cargables': [15, 25, 35, 45],
      },
    );
    final team = await r.team('c1');
    expect(team.cargables, [15, 25, 35, 45]);
    await r.saveTeam('c1', team);
    expect(
      show(requests.last),
      'PUT /clubes/c1/equipo {"barraKg":15.0,"paresDiscos":[10.0,5.0]}',
    );
  });
}
