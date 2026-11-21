import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/history/session_history/session_history.dart';
import 'package:maktub_backend/features/history/session_history/session_history_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';
import 'history_fakes.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about.
class _FakeStore implements SessionHistoryStore {
  final athletes = <(String, String), String>{}; // (clubId, athleteId) -> userId
  final sessions = <Session>[];
  final planList = <Plan>[];
  final recordList = <SetRecord>[];
  final times = <BlockTime>[];
  final catalog = <(String, String), String>{}; // (clubId, exerciseId) -> name

  @override
  Future<String?> athleteUserId(String clubId, String athleteId) async => athletes[(clubId, athleteId)];

  @override
  Future<Session?> session(String clubId, String sessionId) async =>
      sessions.where((s) => s.clubId == clubId && s.id == sessionId).firstOrNull;

  @override
  Future<Plan?> plan(String clubId, String planId) async =>
      planList.where((p) => p.clubId == clubId && p.id == planId).firstOrNull;

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId, String athleteId) async => [
    for (final r in recordList)
      if (r.clubId == clubId && r.sessionId == sessionId && r.athleteId == athleteId) r,
  ];

  @override
  Future<List<BlockTime>> blockTimes(String clubId, String sessionId, String athleteId) async => [
    for (final t in times)
      if (t.clubId == clubId && t.sessionId == sessionId && t.athleteIds.contains(athleteId)) t,
  ];

  @override
  Future<Map<String, String>> exerciseNames(String clubId, Set<String> exerciseIds) async {
    return {
      for (final id in exerciseIds) id: ?(catalog[(clubId, id)] ?? catalog[(clubPlataforma, id)]),
    };
  }
}

BlockTime _time(String sessionId, int block, int seconds, {bool interrupted = false, List<String>? athletes}) =>
    BlockTime(
      id: 't-$block-$seconds',
      clubId: 'club-a',
      sessionId: sessionId,
      blockIndex: block,
      blockName: 'Bloque grabado $block',
      athleteIds: athletes ?? const ['ath-1', 'ath-2'],
      start: DateTime.utc(2026, 4, 3, 10),
      end: DateTime.utc(2026, 4, 3, 10).add(Duration(seconds: seconds)),
      interrupted: interrupted,
      auditoria: audit,
    );

Future<Response> _call(ClubContext ctx, _FakeStore store, String athleteId, String sessionId) async {
  final context = _Context();
  when(() => context.request).thenReturn(Request('GET', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()((c) => sessionHistoryEndpoint(c, athleteId, sessionId, store: store))(context);
}

Future<SessionHistory> _read(Response r) async =>
    SessionHistory.fromJson(jsonDecode(await r.body()) as Json);

void main() {
  const coach = ClubContext(clubId: 'club-a', userId: 'coach-1', roles: {Rol.coach}, clubType: TipoClub.club);
  const athlete1 = ClubContext(clubId: 'club-a', userId: 'user-1', roles: {Rol.atleta}, clubType: TipoClub.club);
  const clubAdmin = ClubContext(
    clubId: 'club-a',
    userId: 'admin-1',
    roles: {Rol.adminClub},
    clubType: TipoClub.club,
  );

  _FakeStore seeded() => _FakeStore()
    ..athletes[('club-a', 'ath-1')] = 'user-1'
    ..athletes[('club-a', 'ath-2')] = 'user-2'
    ..planList.add(
      plan(byAthlete: const {'ath-1': AthleteSetLoad(pct: 70, kg: 72.5), 'ath-2': AthleteSetLoad(pct: 70, kg: 50)}),
    )
    ..catalog[(clubPlataforma, 'bench')] = 'Press de banca'
    ..sessions.addAll([
      session('s1', date: DateTime.utc(2026, 4, 3), present: ['ath-1', 'ath-2'], note: 'Buen día'),
      session('s-gone', planId: 'p-deleted', date: DateTime.utc(2026, 9, 1)),
      session('s-andi', date: DateTime.utc(2026, 4, 4), present: ['ath-2']),
    ])
    ..recordList.addAll([
      record(
        's1',
        set: 0,
        kg: 72.5,
        reps: 5,
        workFactor: 95,
        pctReal: 66.5,
        target: const PlanSet(reps: 5, pct: 70, byAthlete: {'ath-2': AthleteSetLoad(kg: 50)}),
        note: 'Rodilla bien',
      ),
      record('s1', set: 1, kg: 77.5, reps: 5, estimated: true, target: const PlanSet(reps: 5, pct: 75)),
      record('s1', set: 2, done: false, target: const PlanSet(reps: 5, pct: 80)),
      // A set the plan no longer has.
      record('s1', block: 0, prescription: 5, set: 0, exerciseId: 'curl', exerciseName: 'Curl', reps: 12),
      record('s1', athleteId: 'ath-2', set: 0, kg: 999),
      record('s-gone', block: 1, exerciseId: 'row', exerciseName: 'Remo', kg: 60, reps: 10),
      record('s-gone', block: 1, set: 1, exerciseId: 'row', exerciseName: '', kg: 60, reps: 10),
    ])
    ..times.addAll([
      _time('s1', 0, 600),
      _time('s1', 0, 300, interrupted: true),
      _time('s1', 1, 120),
      _time('s1', 2, 999, athletes: ['ath-2']),
      _time('s-gone', 1, 400),
    ]);

  test('the detail merges the plan day with what the athlete recorded', () async {
    final r = await _call(coach, seeded(), 'ath-1', 's1');
    expect(r.statusCode, HttpStatus.ok);
    final h = await _read(r);
    expect(h.entry.sessionId, 's1');
    expect(h.entry.planName, 'Abril 2026');
    expect(h.entry.dayName, 'Pierna');
    // 5 planned + the curl set the plan lost; squat sets 0 and 1 and the curl done.
    expect([h.entry.done, h.entry.total, h.entry.estimated], [3, 6, 1]);
    expect(h.note, 'Buen día');

    expect([for (final b in h.blocks) b.index], [0, 1]);
    final main = h.blocks[0];
    expect(main.name, 'Principal');
    expect(main.seconds, 900);
    expect(main.interrupted, isTrue);
    expect([for (final e in main.exercises) e.index], [0, 1, 5]);

    final squat = main.exercises[0];
    expect(squat.exerciseName, 'Sentadilla');
    expect(squat.note, 'Rodilla bien');
    expect([for (final s in squat.sets) s.record?.kg], [72.5, 77.5, null]);
    expect([for (final s in squat.sets) s.record?.done], [true, true, false]);
    expect(squat.sets[1].record!.estimated, isTrue);

    // Bench has nothing recorded: plan targets, name from the catalog.
    final bench = main.exercises[1];
    expect(bench.exerciseName, 'Press de banca');
    expect([for (final s in bench.sets) (s.target.reps, s.record)], [(8, null), (8, null)]);

    expect(main.exercises[2].exerciseName, 'Curl');
    expect(main.exercises[2].sets.single.record!.reps, 12);

    // A block without exercises shows only for the time the athlete has in it.
    expect(h.blocks[1].name, 'Movilidad');
    expect(h.blocks[1].seconds, 120);
    expect(h.blocks[1].exercises, isEmpty);
  });

  test('targets keep only this athlete\'s frozen load', () async {
    final h = await _read(await _call(coach, seeded(), 'ath-1', 's1'));
    final squat = h.blocks[0].exercises[0];
    // The recorded target had only Andi's load: it goes.
    expect(squat.sets[0].target.byAthlete, isEmpty);
    expect(squat.sets[0].target.pct, 70);
    final h2 = await _read(await _call(coach, seeded(), 'ath-2', 's1'));
    final andiSquat = h2.blocks[0].exercises[0];
    expect(andiSquat.sets[0].record!.kg, 999);
    // Andi did not record set 1: the plan's target, with only Andi's load (none on that set).
    expect(andiSquat.sets[1].record, isNull);
    final body = await (await _call(coach, seeded(), 'ath-2', 's1')).body();
    expect(body, isNot(contains('72.5')));
  });

  test('a planned set the athlete did not record carries their own frozen load', () async {
    final store = seeded()..recordList.removeWhere((r) => r.sessionId == 's1' && r.athleteId == 'ath-1');
    final h = await _read(await _call(coach, store, 'ath-1', 's1'));
    final first = h.blocks[0].exercises[0].sets[0];
    expect(first.record, isNull);
    expect(first.target.byAthlete.keys, ['ath-1']);
    expect(first.target.byAthlete['ath-1']!.kg, 72.5);
  });

  test('a deleted plan still shows the records, names and times', () async {
    final h = await _read(await _call(coach, seeded(), 'ath-1', 's-gone'));
    expect(h.entry.planName, isNull);
    expect([h.entry.done, h.entry.total], [2, 2]);
    final block = h.blocks.single;
    expect(block.index, 1);
    expect(block.name, 'Bloque grabado 1');
    expect(block.seconds, 400);
    final row = block.exercises.single;
    expect(row.exerciseName, 'Remo');
    expect(row.sets, hasLength(2));
  });

  test('the athlete gets their own detail without the work factor or real percent', () async {
    final r = await _call(athlete1, seeded(), 'ath-1', 's1');
    expect(r.statusCode, HttpStatus.ok);
    final body = await r.body();
    expect(body, isNot(contains('"factor"')));
    expect(body, isNot(contains('pctReal')));
    final coachBody = await (await _call(coach, seeded(), 'ath-1', 's1')).body();
    expect(coachBody, contains('"factor":95'));
  });

  test("another athlete's session, a session the athlete was not in or one of another club: the same 404", () async {
    final store = seeded()..sessions.add(session('s-b', clubId: 'club-b', date: DateTime.utc(2026, 4, 3)));
    final foreign = await _call(athlete1, store, 'ath-2', 's1');
    final notIn = await _call(athlete1, store, 'ath-1', 's-andi');
    final otherClub = await _call(athlete1, store, 'ath-1', 's-b');
    final missing = await _call(coach, store, 'ath-1', 'nope');
    for (final r in [foreign, notIn, otherClub, missing]) {
      expect(r.statusCode, HttpStatus.notFound);
    }
    expect(await foreign.body(), await notIn.body());
    expect(await otherClub.body(), await missing.body());
  });

  test('a club admin reads any athlete\'s session', () async {
    expect((await _call(clubAdmin, seeded(), 'ath-1', 's1')).statusCode, HttpStatus.ok);
  });

  group('club isolation', () {
    final store = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/atletas/ath-1/historial/s1',
      endpoint: (c) => sessionHistoryEndpoint(c, 'ath-1', 's-x', store: store),
      path: '/clubes/{clubId}/atletas/ath-1/historial/s-x',
      action: Accion.verReportesPropios,
      seed: (clubId, marker) {
        store.athletes[(clubId, 'ath-1')] = 'u1';
        store.sessions
          ..removeWhere((s) => s.clubId == clubId)
          ..add(session('s-x', clubId: clubId, date: DateTime.utc(2026, 11, 1), note: marker));
      },
    );
  });
}
