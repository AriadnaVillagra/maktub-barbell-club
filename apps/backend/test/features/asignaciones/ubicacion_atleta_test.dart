import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion_atleta/ubicacion_atleta.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion_atleta/ubicacion_atleta_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements AthleteLocationStore {
  final all = <Assignment>[];

  /// `clubId/athleteId`
  final athletes = <String>{};

  /// `clubId/userId` → athlete id.
  final users = <String, String>{};

  /// `clubId/groupId` → member ids.
  final groups = <String, List<String>>{};

  /// `clubId/planId` of the plans with a published version.
  final published = <String>{};

  @override
  Future<bool> athleteExists(String clubId, String athleteId) async =>
      athletes.contains('$clubId/$athleteId');

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async =>
      users['$clubId/$userId'];

  @override
  Future<Set<String>> groupIdsOf(String clubId, String athleteId) async => {
    for (final MapEntry(:key, :value) in groups.entries)
      if (key.startsWith('$clubId/') && value.contains(athleteId))
        key.substring(clubId.length + 1),
  };

  @override
  Future<List<Assignment>> activeAssignments(
    String clubId, {
    required Set<String> groupIds,
    required String athleteId,
  }) async => [
    for (final a in all)
      if (a.clubId == clubId &&
          a.status == AssignmentStatus.active &&
          (groupIds.contains(a.groupId) || a.athleteId == athleteId))
        a,
  ];

  @override
  Future<Set<String>> publishedPlanIds(
    String clubId,
    Set<String> planIds,
  ) async => {
    for (final id in planIds)
      if (published.contains('$clubId/$id')) id,
  };
}

final _audit = Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 1));

Assignment _assignment(
  String id,
  String clubId, {
  String? groupId,
  String? athleteId,
  String planId = 'p1',
  DateTime? start,
  AssignmentStatus status = AssignmentStatus.active,
}) => Assignment(
  id: id,
  clubId: clubId,
  planId: planId,
  groupId: groupId,
  athleteId: athleteId,
  startDate: start ?? DateTime.utc(2026, 11, 2),
  status: status,
  auditoria: _audit,
);

ClubContext _ctx(Set<Rol> roles, {String clubId = 'club-a'}) => ClubContext(
  clubId: clubId,
  userId: 'u-ari',
  roles: roles,
  clubType: TipoClub.club,
);

Future<Response> _get(
  _FakeStore s,
  String query, {
  ClubContext? ctx,
  String athleteId = 'ari',
}) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x$query')));
  when(() => context.read<ClubContext>())
      .thenReturn(ctx ?? _ctx({Rol.atleta}));
  return manejarErrores()(
    (c) => athleteLocationEndpoint(c, athleteId, store: s),
  )(context);
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  _FakeStore store() => _FakeStore()
    ..athletes.addAll(['club-a/ari', 'club-a/andi'])
    ..users['club-a/u-ari'] = 'ari'
    ..groups['club-a/g1'] = ['ari', 'andi']
    ..published.addAll(['club-a/p1', 'club-a/lev'])
    ..all.addAll([
      _assignment('group', 'club-a', groupId: 'g1'),
      _assignment(
        'own',
        'club-a',
        athleteId: 'ari',
        planId: 'lev',
        start: DateTime.utc(2026, 11, 9),
      ),
    ]);

  test("the group's plan and the athlete's own, group first, each placed by its own start", () async {
    final r = await _get(store(), '?fecha=2026-11-16');

    expect(r.statusCode, HttpStatus.ok);
    expect(await _json(r), {
      'fecha': '2026-11-16',
      'ubicaciones': [
        {
          'asignacion': {
            'id': 'group',
            'planId': 'p1',
            'fechaInicio': '2026-11-02',
            'grupoId': 'g1',
          },
          'ciclo': 1,
          'semana': 3,
        },
        {
          'asignacion': {
            'id': 'own',
            'planId': 'lev',
            'fechaInicio': '2026-11-09',
            'atletaId': 'ari',
          },
          'ciclo': 1,
          'semana': 2,
        },
      ],
    });
  });

  test("another athlete's own plan, an ended one and another group's do not count", () async {
    final s = store()
      ..groups['club-a/g2'] = ['andi']
      ..all.addAll([
        _assignment('andi-own', 'club-a', athleteId: 'andi'),
        _assignment('g2', 'club-a', groupId: 'g2'),
        _assignment(
          'old',
          'club-a',
          athleteId: 'ari',
          status: AssignmentStatus.ended,
        ),
      ]);
    final json = await _json(await _get(s, '?fecha=2026-11-16'));

    expect(
      [for (final u in json['ubicaciones'] as List) u['asignacion']['id']],
      ['group', 'own'],
    );
  });

  test('without active assignments the list is empty', () async {
    final s = store()..all.clear();

    expect(await _json(await _get(s, '?fecha=2026-11-16')), {
      'fecha': '2026-11-16',
      'ubicaciones': <Object>[],
    });
  });

  test('an athlete only asks about themselves; a coach about anyone', () async {
    expect(
      (await _get(store(), '?fecha=2026-11-16', athleteId: 'andi')).statusCode,
      HttpStatus.notFound,
    );
    final coach = await _get(
      store(),
      '?fecha=2026-11-16',
      athleteId: 'andi',
      ctx: _ctx({Rol.coach}),
    );
    expect(coach.statusCode, HttpStatus.ok);
    expect(
      [
        for (final u in (await _json(coach))['ubicaciones'] as List)
          u['asignacion']['id'],
      ],
      ['group'],
    );
  });

  test('an unknown athlete is 404, a bad date 400, an unpublished plan 422', () async {
    expect(
      (await _get(store(), '?fecha=2026-11-16', athleteId: 'x', ctx: _ctx({Rol.coach}))).statusCode,
      HttpStatus.notFound,
    );
    expect((await _get(store(), '?fecha=16/11')).statusCode, HttpStatus.badRequest);
    expect(
      (await _get(store()..published.remove('club-a/lev'), '?fecha=2026-11-16')).statusCode,
      HttpStatus.unprocessableEntity,
    );
  });

  group('club isolation', () {
    final s = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/atletas/{athleteId}/ubicacion',
      endpoint: (c) => athleteLocationEndpoint(c, 'ari', store: s),
      path: '/clubes/{clubId}/atletas/ari/ubicacion?fecha=2026-11-16',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) {
        s.athletes.add('$clubId/ari');
        s.published.add('$clubId/$marker');
        s.all.removeWhere((a) => a.clubId == clubId);
        s.all.add(_assignment('own', clubId, athleteId: 'ari', planId: marker));
      },
    );
  });
}
