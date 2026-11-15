import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/asignacion/data/cached_calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/data/http_assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/data/http_calendar_repository.dart';

/// The requests the repositories send and the answers they parse (E8.8: athlete's location, days by assignment and
/// assigning to an athlete).
void main() {
  late List<http.Request> sent;

  ClienteApi client(Object body) => ClienteApi(
    base: Uri.parse('http://api.test'),
    cliente: MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() => sent = []);

  test(
    "an athlete's location lists their group's plan and their own",
    () async {
      final repo = HttpCalendarRepository(
        client({
          'fecha': '2026-11-06',
          'ubicaciones': [
            {
              'asignacion': {
                'id': 'g',
                'planId': 'p1',
                'fechaInicio': '2026-10-01',
                'grupoId': 'g1',
              },
              'ciclo': 2,
              'semana': 1,
            },
            {
              'asignacion': {
                'id': 'own',
                'planId': 'lev',
                'fechaInicio': '2026-11-06',
                'atletaId': 'ari',
              },
              'ciclo': 1,
              'semana': 1,
            },
          ],
        }),
      );

      final located = await repo.locateAthlete(
        'c1',
        'ari',
        DateTime.utc(2026, 11, 6),
      );

      expect(
        sent.single.url.toString(),
        'http://api.test/clubes/c1/atletas/ari/ubicacion?fecha=2026-11-06',
      );
      expect(
        [for (final l in located) (l.assignmentId, l.groupId, l.athleteId)],
        [('g', 'g1', null), ('own', null, 'ari')],
      );
      expect((located.last.cycle, located.last.week), (1, 1));
      // The device's copy keeps whose each one is.
      expect(locationFromJson(locationToJson(located.last)).athleteId, 'ari');
    },
  );

  test('day states are read by assignment', () async {
    final repo = HttpCalendarRepository(
      client({
        'asignacion': {'id': 'own'},
        'dias': [
          {'ciclo': 1, 'semana': 1, 'dia': 1, 'estado': 'hecho'},
        ],
      }),
    );

    final states = await repo.dayStates(
      'c1',
      'own',
      DateTime.utc(2026, 11, 6),
      DateTime.utc(2026, 12, 3),
    );

    expect(sent.single.url.path, '/clubes/c1/asignaciones/own/dias');
    expect(states.single.done, isTrue);
  });

  test('assigning to an athlete sends atletaId and no grupoId', () async {
    final repo = HttpAssignmentRepository(
      client({
        'id': 'a1',
        'clubId': 'c1',
        'planId': 'p1',
        'atletaId': 'ari',
        'fechaInicio': '2026-11-16',
        'estado': 'activa',
        'auditoria': Auditoria(
          creadoPor: 'u1',
          creadoEn: DateTime.utc(2026, 11, 15),
        ).toJson(),
      }),
    );

    final a = await repo.assign(
      'c1',
      planId: 'p1',
      athleteId: 'ari',
      startDate: DateTime.utc(2026, 11, 16),
    );

    expect(jsonDecode(sent.single.body), {
      'planId': 'p1',
      'atletaId': 'ari',
      'fechaInicio': '2026-11-16',
    });
    expect(a.athleteId, 'ari');
  });
}
