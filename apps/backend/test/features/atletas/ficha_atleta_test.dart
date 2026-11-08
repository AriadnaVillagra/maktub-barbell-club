import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/atletas/ficha_atleta/ficha_atleta.dart';
import 'package:maktub_backend/features/atletas/ficha_atleta/ficha_atleta_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about.
class _FakeStore implements AthleteSheetStore {
  final athletes =
      <(String, String), String>{}; // (clubId, athleteId) -> userId
  final refs = <Reference>[];
  final factors = <WorkFactor>[];
  final weights = <FixedWeight>[];

  @override
  Future<String?> athleteUserId(String clubId, String athleteId) async =>
      athletes[(clubId, athleteId)];

  @override
  Future<List<Reference>> references(String clubId, String athleteId) async => [
    for (final r in refs)
      if (r.clubId == clubId && r.athleteId == athleteId) r,
  ];

  @override
  Future<List<WorkFactor>> workFactors(String clubId, String athleteId) async =>
      [
        for (final f in factors)
          if (f.clubId == clubId && f.athleteId == athleteId) f,
      ];

  @override
  Future<List<FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
  ) async => [
    for (final w in weights)
      if (w.clubId == clubId && w.athleteId == athleteId) w,
  ];
}

Reference _rm(String id, String clubId, String athleteId, double value) =>
    Reference(
      id: id,
      clubId: clubId,
      athleteId: athleteId,
      exerciseId: 'squat',
      type: ReferenceType.rm,
      value: value,
      date: DateTime.utc(2026, 11, 1),
      origin: ReferenceOrigin.testeado,
      auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 1)),
    );

Future<Response> _call(
  ClubContext ctx,
  _FakeStore store,
  String athleteId,
) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(
    (c) => athleteSheetEndpoint(c, athleteId, store: store),
  )(context);
}

void main() {
  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const otherClubCoach = ClubContext(
    clubId: 'club-b',
    userId: 'coach-2',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const athlete1 = ClubContext(
    clubId: 'club-a',
    userId: 'user-1',
    roles: {Rol.atleta},
    clubType: TipoClub.club,
  );
  const clubAdmin = ClubContext(
    clubId: 'club-a',
    userId: 'admin-1',
    roles: {Rol.adminClub},
    clubType: TipoClub.club,
  );

  _FakeStore seeded() {
    final store = _FakeStore()
      ..athletes[('club-a', 'ath-1')] = 'user-1'
      ..athletes[('club-a', 'ath-2')] = 'user-2'
      ..refs.addAll([
        _rm('r1', 'club-a', 'ath-1', 140),
        _rm('r2', 'club-a', 'ath-1', 150),
        _rm('r3', 'club-a', 'ath-2', 999),
      ])
      ..factors.add(
        WorkFactor(
          id: 'f1',
          clubId: 'club-a',
          athleteId: 'ath-1',
          exerciseId: 'squat',
          value: 90,
          date: DateTime.utc(2026, 11, 2),
          auditoria: Auditoria.nueva(
            'coach-1',
            ahora: DateTime.utc(2026, 11, 2),
          ),
        ),
      )
      ..weights.add(
        FixedWeight(
          id: 'w1',
          clubId: 'club-a',
          athleteId: 'ath-1',
          exerciseId: 'db-press',
          kg: 30,
          auditoria: Auditoria.nueva(
            'coach-1',
            ahora: DateTime.utc(2026, 11, 2),
          ),
        ),
      );
    return store;
  }

  Future<Json> read(Response r) async => jsonDecode(await r.body()) as Json;

  test('the coach reads any athlete with the full history', () async {
    final store = seeded();
    final r = await _call(coach, store, 'ath-1');
    expect(r.statusCode, HttpStatus.ok);
    final sheet = await read(r);
    expect(sheet['atletaId'], 'ath-1');
    expect(
      (sheet['referencias'] as List).map((e) => (e as Map)['id']),
      unorderedEquals(['r1', 'r2']),
    );
    expect(sheet['factores'], hasLength(1));
    expect(sheet['kilajes'], hasLength(1));
    final other = await read(await _call(coach, store, 'ath-2'));
    expect(other['referencias'], hasLength(1));
  });

  test('an athlete reads their own sheet', () async {
    final r = await _call(athlete1, seeded(), 'ath-1');
    expect(r.statusCode, HttpStatus.ok);
    expect((await read(r))['referencias'], hasLength(2));
  });

  test(
    'an athlete asking for another athlete of the club gets a 404 with no data',
    () async {
      final r = await _call(athlete1, seeded(), 'ath-2');
      expect(r.statusCode, HttpStatus.notFound);
      final text = await r.body();
      expect(text, isNot(contains('999')));
      expect(text, isNot(contains('r3')));
      expect(text, isNot(contains('referencias')));
    },
  );

  test(
    'a missing athlete answers like another athlete (no existence leak)',
    () async {
      final store = seeded();
      final missing = await _call(athlete1, store, 'nope');
      final foreign = await _call(athlete1, store, 'ath-2');
      expect(missing.statusCode, foreign.statusCode);
      expect(await missing.body(), await foreign.body());
    },
  );

  test('the coach asking for a missing athlete gets 404', () async {
    expect(
      (await _call(coach, seeded(), 'nope')).statusCode,
      HttpStatus.notFound,
    );
  });

  test('a coach of another club gets a 404 and no data', () async {
    final r = await _call(otherClubCoach, seeded(), 'ath-1');
    expect(r.statusCode, HttpStatus.notFound);
    expect(await r.body(), isNot(contains('referencias')));
  });

  test('a club admin without reading permission gets a 403', () async {
    expect(
      (await _call(clubAdmin, seeded(), 'ath-1')).statusCode,
      HttpStatus.forbidden,
    );
  });

  group('club isolation', () {
    final store = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/atletas/ath-1',
      endpoint: (c) => athleteSheetEndpoint(c, 'ath-1', store: store),
      path: '/clubes/{clubId}/atletas/ath-1',
      action: Accion.verReportesPropios,
      seed: (clubId, marker) {
        store.athletes[(clubId, 'ath-1')] = 'u1';
        store.refs.add(_rm(marker, clubId, 'ath-1', 100));
      },
    );
  });
}
