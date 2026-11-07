import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/catalogo/data/http_catalog_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_draft.dart';

void main() {
  final audit = Auditoria(
    creadoPor: 'u1',
    creadoEn: DateTime.utc(2026, 11, 7),
  ).toJson();

  test('asks the catalog endpoints of the club and parses them', () async {
    final urls = <Uri>[];
    final repo = HttpCatalogRepository(
      ClienteApi(
        base: Uri.parse('http://api.test'),
        cliente: MockClient((req) async {
          urls.add(req.url);
          final body = req.url.path.endsWith('categorias')
              ? {
                  'categorias': [
                    {
                      'id': 'k1',
                      'clubId': 'c1',
                      'nombre': 'Fuerza',
                      'auditoria': audit,
                    },
                  ],
                }
              : {
                  'ejercicios': [
                    {
                      'id': 'e1',
                      'clubId': 'c1',
                      'nombre': 'Sentadilla',
                      'categorias': ['k1'],
                      'auditoria': audit,
                    },
                  ],
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final exercises = await repo.exercises(
      'c1',
      categoryId: 'k1',
      status: CatalogStatus.active,
    );
    final categories = await repo.categories('c1');

    expect(exercises.single.name, 'Sentadilla');
    expect(categories.single.name, 'Fuerza');
    expect(urls[0].path, '/clubes/c1/catalogo/ejercicios');
    expect(urls[0].queryParameters, {'categoria': 'k1', 'estado': 'activo'});
    expect(urls[1].path, '/clubes/c1/catalogo/categorias');
  });

  group('writes', () {
    final exerciseJson = {
      'id': 'e1',
      'clubId': 'c1',
      'nombre': 'Zancada',
      'estado': 'activo',
      'auditoria': audit,
    };

    (HttpCatalogRepository, List<http.Request>) build(
      Map<String, Object?> Function(http.Request) answer, {
      int status = 200,
    }) {
      final requests = <http.Request>[];
      final repo = HttpCatalogRepository(
        ClienteApi(
          base: Uri.parse('http://api.test'),
          cliente: MockClient((req) async {
            requests.add(req);
            return http.Response(
              jsonEncode(answer(req)),
              status,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      return (repo, requests);
    }

    test(
      'creates, edits and changes the status with the contract of E2.4',
      () async {
        final (repo, requests) = build((_) => exerciseJson);
        const draft = ExerciseDraft(
          name: ' Zancada ',
          categoryIds: ['k1'],
          metrics: [Metric.reps],
          muscles: [MuscleShare(groupId: 'g1', weight: MuscleWeight.secondary)],
        );

        expect((await repo.createExercise('c1', draft)).name, 'Zancada');
        await repo.updateExercise('c1', 'e1', draft);
        final archived = await repo.setExerciseStatus(
          'c1',
          'e1',
          CatalogStatus.archived,
        );

        expect(archived.id, 'e1');
        expect(
          [for (final r in requests) '${r.method} ${r.url.path}'],
          [
            'POST /clubes/c1/catalogo/ejercicios',
            'PUT /clubes/c1/catalogo/ejercicios/e1',
            'PATCH /clubes/c1/catalogo/ejercicios/e1',
          ],
        );
        final body = jsonDecode(requests[0].body) as Map<String, dynamic>;
        expect(body['nombre'], 'Zancada');
        expect(body['categorias'], ['k1']);
        expect(body['musculos'], [
          {'grupoId': 'g1', 'peso': 'secundario'},
        ]);
        for (final k in ['id', 'clubId', 'estado', 'auditoria']) {
          expect(body.containsKey(k), isFalse);
        }
        expect(jsonDecode(requests[2].body), {'estado': 'archivado'});
      },
    );

    test('tells apart a deletion from an archive', () async {
      final (repo, requests) = build(
        (_) => {'resultado': 'borrado', 'id': 'e1'},
      );
      expect((await repo.deleteExercise('c1', 'e1')).deleted, isTrue);
      expect(requests.single.method, 'DELETE');

      final (repo2, _) = build(
        (_) => {
          'resultado': 'archivado',
          'id': 'e1',
          'ejercicio': exerciseJson,
        },
      );
      final r = await repo2.deleteExercise('c1', 'e1');
      expect(r.deleted, isFalse);
      expect(r.archived!.id, 'e1');
    });

    test('reads groups and patterns', () async {
      final (repo, requests) = build(
        (req) => req.url.path.endsWith('grupos')
            ? {
                'grupos': [
                  {
                    'id': 'g1',
                    'clubId': 'plataforma',
                    'nombre': 'Hombro',
                    'auditoria': audit,
                  },
                ],
              }
            : {
                'patrones': [
                  {
                    'id': 'p1',
                    'clubId': 'plataforma',
                    'nombre': 'Empuje',
                    'auditoria': audit,
                  },
                ],
              },
      );
      expect((await repo.muscleGroups('c1')).single.name, 'Hombro');
      expect((await repo.patterns('c1')).single.name, 'Empuje');
      expect(requests.map((r) => r.url.path), [
        '/clubes/c1/catalogo/grupos',
        '/clubes/c1/catalogo/patrones',
      ]);
    });

    test('surfaces the backend message', () async {
      final (repo, _) = build(
        (_) => {'error': 'Ya hay un ejercicio con ese nombre.'},
        status: 409,
      );
      await expectLater(
        repo.createExercise('c1', const ExerciseDraft(name: 'X')),
        throwsA(
          isA<ErrorDeApi>().having(
            (e) => e.mensaje,
            'mensaje',
            'Ya hay un ejercicio con ese nombre.',
          ),
        ),
      );
    });
  });
}
