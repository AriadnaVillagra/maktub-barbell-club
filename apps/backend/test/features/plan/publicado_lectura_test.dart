import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/publicado/publicado.dart';
import 'package:maktub_backend/features/plan/publicado/publicado_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements ReadPublishedPlanStore {
  final all = <Plan>[];

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    for (final p in all) {
      if (p.clubId == clubId && p.id == planId) return p;
    }
    return null;
  }
}

final _t0 = DateTime.utc(2026, 11, 1, 10);

WeekModel _model(String dayName) => WeekModel(
  id: 'A',
  name: 'A',
  days: [PlanDay(name: dayName, blocks: const [])],
);

Plan _plan(
  String id,
  String clubId, {
  String name = 'Octubre',
  String draftDay = 'Borrador',
  String? publishedDay,
}) => Plan(
  id: id,
  clubId: clubId,
  name: name,
  type: PlanType.regular,
  weekModels: [_model(draftDay)],
  weekAssignment: const ['A', 'A', 'A', 'A'],
  published: publishedDay == null
      ? null
      : PublishedPlan(
          weekModels: [_model(publishedDay)],
          weekAssignment: const ['A', 'A', 'A', 'A'],
          publishedAt: _t0,
          publishedBy: 'coach-1',
        ),
  auditoria: Auditoria.nueva('coach-1', ahora: _t0),
);

ClubContext _ctx(String clubId, Set<Rol> roles) => ClubContext(
  clubId: clubId,
  userId: 'u-1',
  roles: roles,
  clubType: TipoClub.club,
);

Future<Response> _call(ClubContext ctx, _FakeStore store, String planId) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(
    (c) => readPublishedPlanEndpoint(c, planId, store: store),
  )(context);
}

void main() {
  late _FakeStore store;
  setUp(() => store = _FakeStore());

  test('returns the published copy and never the draft', () async {
    store.all.add(_plan('p1', 'club-a', publishedDay: 'Publicado'));
    final r = await _call(_ctx('club-a', {Rol.atleta}), store, 'p1');
    expect(r.statusCode, HttpStatus.ok);
    final text = await r.body();
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json.keys.toSet(), {
      'id',
      'nombre',
      'tipo',
      'modelosSemana',
      'asignacion',
      'publicadoEn',
    });
    expect(json['id'], 'p1');
    expect(json['nombre'], 'Octubre');
    expect(json['asignacion'], ['A', 'A', 'A', 'A']);
    expect(json['publicadoEn'], '2026-11-01T10:00:00.000Z');
    expect(text, contains('Publicado'));
    expect(text, isNot(contains('Borrador')));
  });

  test('404 when the plan has no published version', () async {
    store.all.add(_plan('p1', 'club-a'));
    final r = await _call(_ctx('club-a', {Rol.coach}), store, 'p1');
    expect(r.statusCode, HttpStatus.notFound);
    expect(await r.body(), isNot(contains('Borrador')));
  });

  test('404 when the plan is not in the club', () async {
    store.all.add(_plan('p1', 'club-b', publishedDay: 'Publicado'));
    final r = await _call(_ctx('club-a', {Rol.coach}), store, 'p1');
    expect(r.statusCode, HttpStatus.notFound);
  });

  group('club isolation', () {
    final isolationStore = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/planes/{planId}/publicado',
      endpoint: (c) =>
          readPublishedPlanEndpoint(c, 'shared-id', store: isolationStore),
      path: '/clubes/{clubId}/planes/shared-id/publicado',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) {
        isolationStore.all.removeWhere(
          (p) => p.id == 'shared-id' && p.clubId == clubId,
        );
        isolationStore.all.add(
          _plan('shared-id', clubId, publishedDay: marker),
        );
      },
    );
  });
}
