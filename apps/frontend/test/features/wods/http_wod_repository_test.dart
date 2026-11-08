import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/wods/data/http_wod_repository.dart';
import 'package:maktub_frontend/features/wods/domain/wod_draft.dart';
import 'package:maktub_frontend/features/wods/domain/wod_repository.dart';

import 'fakes.dart';

void main() {
  final requests = <(String, String, Object?)>[];

  HttpWodRepository repo(http.Response Function(http.Request) answer) {
    requests.clear();
    return HttpWodRepository(
      ClienteApi(
        base: Uri.parse('http://api.test'),
        cliente: MockClient((req) async {
          requests.add((
            req.method,
            req.url.path,
            req.body.isEmpty ? null : jsonDecode(req.body),
          ));
          return answer(req);
        }),
      ),
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('lists, creates, saves and deletes with the verbs of the API', () async {
    final wod = sampleWod(name: 'Fran').toJson();
    final r = repo(
      (req) => switch (req.method) {
        'GET' => json([wod]),
        'POST' => json(wod, 201),
        'PUT' => json(wod),
        _ => http.Response('', 204),
      },
    );
    expect((await r.wods('c1')).single.name, 'Fran');
    await r.create('c1', const WodDraft(name: 'Fran'));
    await r.save('c1', 'w 1', const WodDraft(name: 'Fran'));
    await r.delete('c1', 'w 1');
    expect(
      [for (final q in requests) '${q.$1} ${q.$2}'],
      [
        'GET /clubes/c1/wods',
        'POST /clubes/c1/wods',
        'PUT /clubes/c1/wods/w%201',
        'DELETE /clubes/c1/wods/w%201',
      ],
    );
    expect(requests[1].$3, {'nombre': 'Fran', 'prescripciones': <Object>[]});
  });

  test('a 422 with problems becomes WodRejected', () async {
    final r = repo(
      (_) => json({
        'error': 'El WoD tiene 2 problema(s); no se guardó.',
        'problemas': [
          {'codigo': 'nameEmpty'},
          {'codigo': 'prescriptionWithoutExercise', 'prescripcion': 1},
        ],
      }, 422),
    );
    await expectLater(
      r.create('c1', const WodDraft()),
      throwsA(
        isA<WodRejected>().having((e) => e.problems, 'problems', const [
          WodProblem(WodProblemCode.nameEmpty),
          WodProblem(
            WodProblemCode.prescriptionWithoutExercise,
            prescriptionIndex: 1,
          ),
        ]),
      ),
    );
  });

  test('a 422 with an unknown code and other errors stay ErrorDeApi', () async {
    final unknown = repo(
      (_) => json({
        'error': 'Raro',
        'problemas': [
          {'codigo': 'nuevo'},
        ],
      }, 422),
    );
    await expectLater(
      unknown.save('c1', 'w1', const WodDraft()),
      throwsA(isA<ErrorDeApi>().having((e) => e.mensaje, 'message', 'Raro')),
    );
    final missing = repo((_) => json({'error': 'WoD no encontrado.'}, 404));
    await expectLater(
      missing.save('c1', 'w1', const WodDraft()),
      throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'status', 404)),
    );
  });
}
