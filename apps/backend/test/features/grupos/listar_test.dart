import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/grupos/listar/listar.dart';
import 'package:maktub_backend/features/grupos/listar/listar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only returns the groups of the club it is asked about.
class _FakeStore implements ListGroupsStore {
  final all = <AthleteGroup>[];

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    for (final g in all)
      if (g.clubId == clubId) g,
  ];
}

AthleteGroup _group(
  String id,
  String clubId,
  String name, {
  List<String>? members,
}) => AthleteGroup(
  id: id,
  clubId: clubId,
  name: name,
  memberIds: members ?? const ['a1', 'a2'],
  auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 8)),
);

Future<Response> _call(ClubContext ctx, _FakeStore store) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()((c) => listGroupsEndpoint(c, store: store))(context);
}

void main() {
  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const athleteOnly = ClubContext(
    clubId: 'club-a',
    userId: 'user-1',
    roles: {Rol.atleta},
    clubType: TipoClub.club,
  );

  test('a coach lists the groups of the club with their members', () async {
    final store = _FakeStore()
      ..all.addAll([
        _group('g2', 'club-a', 'beta', members: ['a3']),
        _group('g1', 'club-a', 'Alpha'),
        _group('g9', 'club-b', 'Other'),
      ]);

    final r = await _call(coach, store);

    expect(r.statusCode, HttpStatus.ok);
    final body = jsonDecode(await r.body()) as List;
    expect([for (final g in body) (g as Map)['nombre']], ['Alpha', 'beta']);
    expect((body.first as Map)['miembros'], ['a1', 'a2']);
    expect(
      AthleteGroup.fromJson((body.last as Map).cast<String, dynamic>())
          .memberIds,
      ['a3'],
    );
  });

  test('an athlete can list the groups too', () async {
    final r = await _call(
      athleteOnly,
      _FakeStore()..all.add(_group('g1', 'club-a', 'Alpha')),
    );

    expect(r.statusCode, HttpStatus.ok);
    expect(await r.body(), contains('Alpha'));
  });

  test('a club without groups answers an empty list', () async {
    final r = await _call(coach, _FakeStore());

    expect(r.statusCode, HttpStatus.ok);
    expect(jsonDecode(await r.body()), isEmpty);
  });

  group('club isolation', () {
    final store = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/grupos',
      endpoint: (c) => listGroupsEndpoint(c, store: store),
      path: '/clubes/{clubId}/grupos',
      action: Accion.verCatalogoYPlanes,
      seed: (clubId, marker) =>
          store.all.add(_group('id-$marker', clubId, marker)),
    );
  });
}
