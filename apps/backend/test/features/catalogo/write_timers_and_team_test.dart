import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/archive_timer/archive_timer.dart';
import 'package:maktub_backend/features/catalogo/archive_timer/archive_timer_store.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer_store.dart';
import 'package:maktub_backend/features/catalogo/delete_timer/delete_timer.dart';
import 'package:maktub_backend/features/catalogo/delete_timer/delete_timer_store.dart';
import 'package:maktub_backend/features/catalogo/get_team/get_team.dart';
import 'package:maktub_backend/features/catalogo/get_team/get_team_store.dart';
import 'package:maktub_backend/features/catalogo/save_team/save_team.dart';
import 'package:maktub_backend/features/catalogo/save_team/save_team_store.dart';
import 'package:maktub_backend/features/catalogo/update_timer/update_timer.dart';
import 'package:maktub_backend/features/catalogo/update_timer/update_timer_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

/// One fake for every timer slice: like Mongo, it only touches what the club is allowed to.
class _FakeTimers implements CreateTimerStore, UpdateTimerStore, ArchiveTimerStore, DeleteTimerStore, TimerUsage {
  final timers = <Temporizador>[];
  final used = <String>{};

  @override
  Future<void> insert(Temporizador timer) async => timers.add(timer);

  @override
  Future<Temporizador?> findVisible(String clubId, String id) async {
    for (final t in timers) {
      if (t.id == id && (t.clubId == clubId || t.clubId == clubPlataforma)) return t;
    }
    return null;
  }

  @override
  Future<void> replace(Temporizador timer) async {
    final i = timers.indexWhere((t) => t.id == timer.id && t.clubId == timer.clubId);
    if (i >= 0) timers[i] = timer;
  }

  @override
  Future<void> delete(String clubId, String id) async => timers.removeWhere((t) => t.id == id && t.clubId == clubId);

  @override
  Future<bool> isUsed(String clubId, String timerId) async => used.contains(timerId);
}

class _FakeTeams implements GetTeamStore, SaveTeamStore {
  final teams = <String, Equipo>{};

  @override
  Future<Equipo?> find(String clubId) async => teams[clubId];

  @override
  Future<void> upsert(Equipo team) async => teams[team.clubId] = team;
}

void main() {
  final now = DateTime.utc(2026, 11, 7, 12);
  const club = ClubContext(clubId: 'club-a', userId: 'coach-1', roles: {Rol.coach}, clubType: TipoClub.club);
  const athlete = ClubContext(clubId: 'club-a', userId: 'ath-1', roles: {Rol.atleta}, clubType: TipoClub.club);

  Temporizador timer(
    String id,
    String clubId, {
    String name = 'EMOM 10',
    CatalogStatus status = CatalogStatus.active,
  }) => Temporizador(
    id: id,
    clubId: clubId,
    nombre: name,
    tipo: TipoTemporizador.emom,
    trabajoSeg: 60,
    rondas: 10,
    estado: status,
    auditoria: Auditoria.nueva('u0', ahora: now),
  );

  Matcher rejects(int status) => throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', status));

  group('create timer', () {
    test('creates a club timer with the server setting id, scope, status and audit', () async {
      final store = _FakeTimers();
      final created = await CreateTimer(store, now: () => now, newId: () => 'new-1')(club, {
        'id': 'forged',
        'clubId': 'plataforma',
        'estado': 'archivado',
        'nombre': 'Tabata',
        'tipo': 'tabata',
        'trabajoSeg': 20,
        'descansoSeg': 10,
        'rondas': 8,
      });
      expect(created.id, 'new-1');
      expect(created.clubId, 'club-a');
      expect(created.estado, CatalogStatus.active);
      expect(created.auditoria!.creadoPor, 'coach-1');
      expect(created.auditoria!.creadoEn, now);
      expect(store.timers.single.nombre, 'Tabata');
    });

    test('rejects an invalid timer', () {
      final create = CreateTimer(_FakeTimers());
      expect(create(club, {'nombre': ' ', 'tipo': 'emom', 'trabajoSeg': 0}), rejects(HttpStatus.badRequest));
    });

    test('the endpoint rejects an athlete', () async {
      final r = await _call(athlete, (c) => createTimerEndpoint(c, store: _FakeTimers()), 'POST', {'nombre': 'x'});
      expect(r.statusCode, HttpStatus.forbidden);
    });
  });

  group('update timer', () {
    test('edits the club timer and stamps who modified it', () async {
      final store = _FakeTimers()..timers.add(timer('t1', 'club-a'));
      final edited = await UpdateTimer(store, now: () => now)(club, 't1', {
        'nombre': 'EMOM 12',
        'rondas': 12,
        'clubId': 'club-b',
      });
      expect(edited.nombre, 'EMOM 12');
      expect(edited.rondas, 12);
      expect(edited.clubId, 'club-a');
      expect(edited.auditoria!.creadoPor, 'u0');
      expect(edited.auditoria!.modificadoPor, 'coach-1');
      expect(store.timers.single.rondas, 12);
    });

    test('rejects editing a base timer', () async {
      final store = _FakeTimers()..timers.add(timer('base-1', clubPlataforma));
      await expectLater(UpdateTimer(store)(club, 'base-1', {'nombre': 'Mío'}), rejects(HttpStatus.forbidden));
      expect(store.timers.single.nombre, 'EMOM 10');
    });

    test('does not find a timer of another club', () {
      final store = _FakeTimers()..timers.add(timer('t1', 'club-b'));
      expect(UpdateTimer(store)(club, 't1', {}), rejects(HttpStatus.notFound));
    });
  });

  group('archive timer', () {
    test('archives a club timer', () async {
      final store = _FakeTimers()..timers.add(timer('t1', 'club-a'));
      final archived = await ArchiveTimer(store, now: () => now)(club, 't1');
      expect(archived.estado, CatalogStatus.archived);
      expect(store.timers.single.estado, CatalogStatus.archived);
    });

    test('rejects archiving a base timer', () {
      final store = _FakeTimers()..timers.add(timer('base-1', clubPlataforma));
      expect(ArchiveTimer(store)(club, 'base-1'), rejects(HttpStatus.forbidden));
    });
  });

  group('delete timer', () {
    test('deletes an unused timer', () async {
      final store = _FakeTimers()..timers.add(timer('t1', 'club-a'));
      expect(await DeleteTimer(store, store)(club, 't1'), DeleteTimerResult.borrado);
      expect(store.timers, isEmpty);
    });

    test('archives instead of deleting a used timer', () async {
      final store = _FakeTimers()
        ..timers.add(timer('t1', 'club-a'))
        ..used.add('t1');
      expect(await DeleteTimer(store, store, now: () => now)(club, 't1'), DeleteTimerResult.archivado);
      expect(store.timers.single.estado, CatalogStatus.archived);
    });

    test('rejects deleting a base timer', () async {
      final store = _FakeTimers()..timers.add(timer('base-1', clubPlataforma));
      await expectLater(DeleteTimer(store, store)(club, 'base-1'), rejects(HttpStatus.forbidden));
      expect(store.timers, hasLength(1));
    });
  });

  group('team', () {
    test('a club with no saved team gets the standard', () async {
      final team = await GetTeam(_FakeTeams())(club);
      expect(team.clubId, 'club-a');
      expect(team.barraKg, 20);
      expect(team.paresDiscos, [20, 15, 10, 5, 2.5, 1.5, 1.25]);
      expect(team.cargables, Equipo.estandar.cargables);
    });

    test('saving a new team changes the loadable weights', () async {
      final store = _FakeTeams();
      final saved = await SaveTeam(store, now: () => now)(club, {
        'barraKg': 15,
        'paresDiscos': [5, 10],
      });
      expect(saved.cargables, [15, 25, 35, 45]);
      expect(saved.paresDiscos, [10, 5]);
      expect(saved.auditoria!.creadoPor, 'coach-1');
      final read = await GetTeam(store)(club);
      expect(read.cargables, [15, 25, 35, 45]);
      expect(read.masCercano(30), 25);

      final again = await SaveTeam(store, now: () => now)(
        const ClubContext(clubId: 'club-a', userId: 'coach-2', roles: {Rol.coach}, clubType: TipoClub.club),
        {
          'barraKg': 20,
          'paresDiscos': [20],
        },
      );
      expect(again.auditoria!.creadoPor, 'coach-1');
      expect(again.auditoria!.modificadoPor, 'coach-2');
      expect(store.teams, hasLength(1), reason: 'one team per club');
    });

    test('rejects an invalid team', () {
      final save = SaveTeam(_FakeTeams());
      expect(
        save(club, {
          'barraKg': 0,
          'paresDiscos': [5],
        }),
        rejects(HttpStatus.badRequest),
      );
      expect(
        save(club, {
          'barraKg': 20,
          'paresDiscos': [5, 5],
        }),
        rejects(HttpStatus.badRequest),
      );
      expect(save(club, {'barraKg': 20, 'paresDiscos': List.filled(13, 1.0)}), rejects(HttpStatus.badRequest));
      expect(save(club, {'barraKg': 20}), rejects(HttpStatus.badRequest));
    });

    test('the club comes from the path, so another club keeps its own team', () async {
      final store = _FakeTeams();
      await SaveTeam(store)(club, {
        'barraKg': 15,
        'paresDiscos': [10],
        'clubId': 'club-b',
      });
      expect(store.teams.keys, ['club-a']);
      expect(
        (await GetTeam(store)(
          const ClubContext(clubId: 'club-b', userId: 'u', roles: {Rol.coach}, clubType: TipoClub.club),
        )).barraKg,
        20,
      );
    });

    test('the write endpoint rejects an athlete, the read endpoint does not', () async {
      final store = _FakeTeams();
      final put = await _call(athlete, (c) => saveTeamEndpoint(c, store: store), 'PUT', {
        'barraKg': 15,
        'paresDiscos': <num>[],
      });
      expect(put.statusCode, HttpStatus.forbidden);
      expect(store.teams, isEmpty);
      final get = await _call(athlete, (c) => getTeamEndpoint(c, store: store), 'GET', null);
      expect(get.statusCode, HttpStatus.ok);
    });
  });

  group('club isolation', () {
    final timers = _FakeTimers();
    final teams = _FakeTeams();

    void seedTimer(String clubId, String marker) {
      timers.timers
        ..removeWhere((t) => t.clubId == clubId)
        ..add(timer('t1', clubId, name: marker));
    }

    void seedTeam(String clubId, String marker) => teams.teams[clubId] = Equipo(
      clubId: clubId,
      auditoria: Auditoria.nueva(marker, ahora: now),
    );

    testClubIsolation(
      'PUT /clubes/{clubId}/temporizadores/t1',
      endpoint: (c) => updateTimerEndpoint(c, 't1', store: timers),
      path: '/clubes/{clubId}/temporizadores/t1',
      action: Accion.planificar,
      method: 'PUT',
      body: '{}',
      seed: seedTimer,
    );
    testClubIsolation(
      'POST /clubes/{clubId}/temporizadores/t1/archivar',
      endpoint: (c) => archiveTimerEndpoint(c, 't1', store: timers),
      path: '/clubes/{clubId}/temporizadores/t1/archivar',
      action: Accion.planificar,
      method: 'POST',
      seed: seedTimer,
    );
    testClubIsolation(
      'GET /clubes/{clubId}/equipo',
      endpoint: (c) => getTeamEndpoint(c, store: teams),
      path: '/clubes/{clubId}/equipo',
      action: Accion.verCatalogoYPlanes,
      seed: seedTeam,
    );
    testClubIsolation(
      'PUT /clubes/{clubId}/equipo',
      endpoint: (c) => saveTeamEndpoint(c, store: teams),
      path: '/clubes/{clubId}/equipo',
      action: Accion.planificar,
      method: 'PUT',
      body: '{"barraKg": 20, "paresDiscos": [20, 10]}',
      seed: seedTeam,
    );

    // The responses of these two don't echo stored data, so only the rejection cases apply.
    for (final (name, endpoint, method, body) in <(String, Handler, String, Object?)>[
      (
        'POST /clubes/{clubId}/temporizadores',
        (c) => createTimerEndpoint(c, store: timers),
        'POST',
        '{"nombre":"x","tipo":"emom","trabajoSeg":60}',
      ),
      (
        'DELETE /clubes/{clubId}/temporizadores/t1',
        (c) => deleteTimerEndpoint(c, 't1', store: timers, usage: timers),
        'DELETE',
        null,
      ),
    ]) {
      final check = ClubIsolationCheck(
        endpoint: endpoint,
        path: name.split(' ').last,
        action: Accion.planificar,
        seed: seedTimer,
        method: method,
        body: body,
      );
      group('club isolation: $name', () {
        test('rejects a user with no membership in the club', check.rejectsNonMember);
        test('rejects a member whose role does not allow the action', check.rejectsWrongRole);
      });
    }
  });
}

/// Runs an endpoint as [ctx] with a request of [method], no routing in between.
Future<Response> _call(ClubContext ctx, Handler endpoint, String method, Object? body) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/x'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return await manejarErrores()(endpoint)(context);
}

class _Context extends Mock implements RequestContext {}
