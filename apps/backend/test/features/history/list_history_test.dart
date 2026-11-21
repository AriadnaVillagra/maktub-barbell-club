import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/history/history_view.dart';
import 'package:maktub_backend/features/history/list_history/list_history.dart';
import 'package:maktub_backend/features/history/list_history/list_history_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';
import 'history_fakes.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about.
class _FakeStore implements ListHistoryStore {
  final athletes = <(String, String), String>{}; // (clubId, athleteId) -> userId
  final sessions = <Session>[];
  final planList = <Plan>[];
  final recordList = <SetRecord>[];
  final calls = <String>[];

  Iterable<Session> _of(String clubId, String athleteId) =>
      sessions.where((s) => s.clubId == clubId && s.presentAthleteIds.contains(athleteId));

  @override
  Future<String?> athleteUserId(String clubId, String athleteId) async => athletes[(clubId, athleteId)];

  @override
  Future<List<Session>> sessionsBefore(
    String clubId,
    String athleteId, {
    DateTime? before,
    required int limit,
  }) async {
    calls.add('before:${before == null ? '-' : aIsoFecha(before)}:$limit');
    final found = [
      for (final s in _of(clubId, athleteId))
        if (before == null || s.date.isBefore(before)) s,
    ]..sort((a, b) => b.date.compareTo(a.date));
    return found.take(limit).toList();
  }

  @override
  Future<List<Session>> sessionsOn(String clubId, String athleteId, DateTime date) async => [
    for (final s in _of(clubId, athleteId))
      if (s.date == date) s,
  ];

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> planIds) async => {
    for (final p in planList)
      if (p.clubId == clubId && planIds.contains(p.id)) p.id: p,
  };

  @override
  Future<List<({String sessionId, RecordMark mark})>> records(
    String clubId,
    String athleteId,
    List<String> sessionIds,
  ) async => [
    for (final r in recordList)
      if (r.clubId == clubId && r.athleteId == athleteId && sessionIds.contains(r.sessionId))
        (sessionId: r.sessionId, mark: markOf(r)),
  ];
}

Future<Response> _call(ClubContext ctx, _FakeStore store, String athleteId, {String query = ''}) async {
  final context = _Context();
  when(() => context.request).thenReturn(Request('GET', Uri.parse('http://localhost/x$query')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()((c) => listHistoryEndpoint(c, athleteId, store: store))(context);
}

Future<Json> _json(Response r) async => jsonDecode(await r.body()) as Json;

List<String> _ids(Json page) => [for (final s in page['sesiones'] as List) '${(s as Map)['sesionId']}'];

void main() {
  const coach = ClubContext(clubId: 'club-a', userId: 'coach-1', roles: {Rol.coach}, clubType: TipoClub.club);
  const athlete1 = ClubContext(clubId: 'club-a', userId: 'user-1', roles: {Rol.atleta}, clubType: TipoClub.club);
  const clubAdmin = ClubContext(
    clubId: 'club-a',
    userId: 'admin-1',
    roles: {Rol.adminClub},
    clubType: TipoClub.club,
  );
  const personal = ClubContext(
    clubId: 'club-a',
    userId: 'user-1',
    roles: {Rol.coach, Rol.atleta},
    clubType: TipoClub.personal,
  );

  _FakeStore seeded() => _FakeStore()
    ..athletes[('club-a', 'ath-1')] = 'user-1'
    ..athletes[('club-a', 'ath-2')] = 'user-2'
    ..planList.addAll([plan(), plan(id: 'p2', name: 'Octubre', type: PlanType.regular)])
    ..sessions.addAll([
      session('s-old', date: DateTime.utc(2025, 5, 10)),
      session('s-apr', date: DateTime.utc(2026, 4, 3)),
      session('s-oct', planId: 'p2', date: DateTime.utc(2026, 10, 1)),
      // A deleted plan (E8.9): its session stays.
      session('s-gone', planId: 'p-deleted', date: DateTime.utc(2026, 9, 1)),
      session('s-andi', date: DateTime.utc(2026, 4, 4), present: ['ath-2']),
    ])
    ..recordList.addAll([
      record('s-apr', set: 0, kg: 70, reps: 5),
      record('s-apr', set: 1, kg: 75, reps: 5, estimated: true),
      record('s-apr', set: 2, done: false),
      record('s-apr', athleteId: 'ath-2', set: 0),
      record('s-gone', exerciseId: 'row', exerciseName: 'Remo', set: 0),
      record('s-gone', exerciseId: 'row', exerciseName: 'Remo', set: 1),
    ]);

  test("the coach lists an athlete's sessions from any plan, newest first", () async {
    final r = await _call(coach, seeded(), 'ath-1');
    expect(r.statusCode, HttpStatus.ok);
    final page = await _json(r);
    expect(_ids(page), ['s-oct', 's-gone', 's-apr', 's-old']);
    expect(page.containsKey('siguiente'), isFalse);
  });

  test('each entry has the plan, the day and the athlete\'s done, total and estimated sets', () async {
    final page = HistoryPage.fromJson(await _json(await _call(coach, seeded(), 'ath-1')));
    final april = page.entries.firstWhere((e) => e.sessionId == 's-apr');
    expect(april.planName, 'Abril 2026');
    expect(april.planType, PlanType.history);
    expect([april.cycle, april.week, april.day], [1, 1, 1]);
    expect(april.dayName, 'Pierna');
    expect(april.date, DateTime.utc(2026, 4, 3));
    // Squat 3 + bench 2 planned; two squat sets done (Andi's set does not count), one estimated.
    expect([april.done, april.total, april.estimated], [2, 5, 1]);

    final gone = page.entries.firstWhere((e) => e.sessionId == 's-gone');
    expect(gone.planName, isNull);
    expect(gone.planType, isNull);
    expect([gone.done, gone.total], [2, 2]);

    final old = page.entries.firstWhere((e) => e.sessionId == 's-old');
    expect([old.done, old.total], [0, 5]);
  });

  test('pages back by date and never splits a date', () async {
    final store = seeded()
      ..sessions.addAll([
        session('s-apr-b', date: DateTime.utc(2026, 4, 3), createdAt: DateTime.utc(2026, 4, 3, 12)),
      ]);
    final first = await _json(await _call(coach, store, 'ath-1', query: '?limite=3'));
    // Three asked for; the oldest date (April 3) has two sessions, so both come.
    expect(_ids(first), ['s-oct', 's-gone', 's-apr-b', 's-apr']);
    expect(first['siguiente'], '2026-04-03');

    final second = await _json(await _call(coach, store, 'ath-1', query: '?limite=3&antesDe=2026-04-03'));
    expect(_ids(second), ['s-old']);
    expect(second.containsKey('siguiente'), isFalse);
    expect(store.calls.last, 'before:2026-04-03:3');
  });

  test('a full last page still says where to go on, and the next one comes empty', () async {
    final store = seeded();
    final first = await _json(await _call(coach, store, 'ath-1', query: '?limite=4'));
    expect(_ids(first), hasLength(4));
    expect(first['siguiente'], '2025-05-10');
    final next = await _json(await _call(coach, store, 'ath-1', query: '?antesDe=2025-05-10'));
    expect(_ids(next), isEmpty);
    expect(next.containsKey('siguiente'), isFalse);
  });

  test('uses the default page size', () async {
    final store = seeded();
    await _call(coach, store, 'ath-1');
    expect(store.calls.single, 'before:-:$defaultHistoryPageSize');
  });

  test('an athlete reads their own history', () async {
    final r = await _call(athlete1, seeded(), 'ath-1');
    expect(r.statusCode, HttpStatus.ok);
    expect(_ids(await _json(r)), hasLength(4));
  });

  test('in the personal club the user reads their own history', () async {
    final r = await _call(personal, seeded(), 'ath-1');
    expect(r.statusCode, HttpStatus.ok);
  });

  test("an athlete asking for another athlete's history gets the same 404 as a missing one", () async {
    final store = seeded();
    final foreign = await _call(athlete1, store, 'ath-2');
    final missing = await _call(athlete1, store, 'nope');
    expect(foreign.statusCode, HttpStatus.notFound);
    final body = await foreign.body();
    expect(body, isNot(contains('s-andi')));
    expect(body, await missing.body());
  });

  test('the coach asking for a missing athlete gets 404', () async {
    expect((await _call(coach, seeded(), 'nope')).statusCode, HttpStatus.notFound);
  });

  test('a club admin without reading permission gets a 403', () async {
    expect((await _call(clubAdmin, seeded(), 'ath-1')).statusCode, HttpStatus.forbidden);
  });

  test('rejects a malformed date or a page size out of range', () async {
    for (final q in ['?antesDe=2026-13-01', '?antesDe=ayer', '?limite=0', '?limite=51', '?limite=x']) {
      final r = await _call(coach, seeded(), 'ath-1', query: q);
      expect(r.statusCode, HttpStatus.badRequest, reason: q);
    }
  });

  group('club isolation', () {
    final store = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/atletas/ath-1/historial',
      endpoint: (c) => listHistoryEndpoint(c, 'ath-1', store: store),
      path: '/clubes/{clubId}/atletas/ath-1/historial',
      action: Accion.verReportesPropios,
      seed: (clubId, marker) {
        store.athletes[(clubId, 'ath-1')] = 'u1';
        store.sessions.add(session(marker, clubId: clubId, date: DateTime.utc(2026, 11, 1)));
      },
    );
  });
}
