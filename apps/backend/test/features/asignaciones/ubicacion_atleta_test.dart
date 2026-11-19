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

  /// `clubId/planId` of the plans with a published version.
  final published = <String>{};

  @override
  Future<({String? userId})?> athlete(String clubId, String athleteId) async {
    if (!athletes.contains('$clubId/$athleteId')) return null;
    final user = users.entries.where((e) => e.key.startsWith('$clubId/') && e.value == athleteId).firstOrNull;
    return (userId: user?.key.substring(clubId.length + 1));
  }

  @override
  Future<List<Assignment>> activeAssignments(
    String clubId,
    String athleteId,
  ) async => [
    for (final a in all)
      if (a.clubId == clubId &&
          a.status == AssignmentStatus.active &&
          a.athleteIds.contains(athleteId))
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
  List<AssignmentMember>? members,
  List<String> athleteIds = const [],
  String planId = 'p1',
  DateTime? start,
  AssignmentStatus status = AssignmentStatus.active,
}) => Assignment(
  id: id,
  clubId: clubId,
  planId: planId,
  groupId: groupId,
  members:
      members ??
      [
        for (final a in athleteIds)
          AssignmentMember(
            athleteId: a,
            from: start ?? DateTime.utc(2026, 11, 2),
          ),
      ],
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
    ..published.addAll(['club-a/p1', 'club-a/lev'])
    ..all.addAll([
      _assignment('group', 'club-a', groupId: 'g1', athleteIds: ['ari', 'andi']),
      _assignment(
        'own',
        'club-a',
        athleteIds: ['ari'],
        planId: 'lev',
        start: DateTime.utc(2026, 11, 9),
      ),
    ]);

  test('every plan the athlete is in, by start date, each placed by its own start', () async {
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
            'atletas': ['ari', 'andi'],
          },
          'ciclo': 1,
          'semana': 3,
        },
        {
          'asignacion': {
            'id': 'own',
            'planId': 'lev',
            'fechaInicio': '2026-11-09',
            'atletas': ['ari'],
          },
          'ciclo': 1,
          'semana': 2,
        },
      ],
    });
  });

  test("another athlete's plan and an ended one do not count", () async {
    final s = store()
      ..all.addAll([
        _assignment('andi-own', 'club-a', athleteIds: ['andi']),
        _assignment(
          'old',
          'club-a',
          athleteIds: ['ari'],
          status: AssignmentStatus.ended,
        ),
      ]);
    final json = await _json(await _get(s, '?fecha=2026-11-16'));

    expect(
      [for (final u in json['ubicaciones'] as List) u['asignacion']['id']],
      ['group', 'own'],
    );
  });

  test('only on the dates the athlete is in the plan (E6.7)', () async {
    final s = store()
      ..all.add(
        _assignment(
          'left',
          'club-a',
          members: [
            AssignmentMember(
              athleteId: 'ari',
              from: DateTime.utc(2026, 11, 2),
              to: DateTime.utc(2026, 11, 10),
            ),
            AssignmentMember(athleteId: 'ari', from: DateTime.utc(2026, 11, 20)),
          ],
        ),
      );
    Future<List<Object?>> ids(String date) async => [
      for (final u in (await _json(await _get(s, '?fecha=$date')))['ubicaciones'] as List)
        u['asignacion']['id'],
    ];

    expect(await ids('2026-11-10'), contains('left'));
    expect(await ids('2026-11-16'), isNot(contains('left')));
    expect(await ids('2026-11-20'), contains('left'));
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
        s.all.add(_assignment('own', clubId, athleteIds: ['ari'], planId: marker));
      },
    );
  });
}
