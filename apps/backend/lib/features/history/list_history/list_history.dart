import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/history/history_view.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'list_history_store.dart';

/// `GET /clubes/{clubId}/atletas/{athleteId}/historial[?antesDe=yyyy-MM-dd][&limite=N]` → 200 [HistoryPage]:
/// `{"sesiones": [HistoryEntry], "siguiente"?: "yyyy-MM-dd"}`, the athlete's past sessions newest first, from any
/// plan or assignment (active, ended, historical or deleted). A session is the athlete's when they are among its
/// present athletes: writing a set makes the writer's athlete present (E7.27) and the importers list theirs, so
/// every session with records of the athlete is one of them.
///
/// `antesDe` (exclusive) pages back: pass the previous page's `siguiente`. `limite` is the number of sessions
/// ([defaultHistoryPageSize] by default, at most [maxHistoryPageSize]); a page can bring more when the oldest
/// date had several sessions, since a date is never split. `siguiente` is missing when nothing older is left.
///
/// Access: see [ensureCanReadHistory]; 404 for an athlete the user cannot read. 400 for a malformed `antesDe` or a
/// `limite` out of range. [store] is for tests.
Future<Response> listHistoryEndpoint(
  RequestContext context,
  String athleteId, {
  ListHistoryStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verReportesPropios);
  final query = context.request.uri.queryParameters;
  final before = query['antesDe'] == null ? null : fechaDeSolicitud(query['antesDe'], 'antesDe');
  final page = await ListHistory(
    store ?? MongoListHistoryStore(context.read<Db>()),
  )(club, athleteId, before: before, limit: _limitOf(query['limite']));
  return Response.json(body: page.toJson());
}

int _limitOf(String? raw) {
  if (raw == null) return defaultHistoryPageSize;
  final limit = int.tryParse(raw.trim());
  if (limit == null || limit < 1 || limit > maxHistoryPageSize) {
    throw const ErrorDeSolicitud('"limite" debe ser un número entre 1 y $maxHistoryPageSize.');
  }
  return limit;
}

class ListHistory {
  ListHistory(this._store);

  final ListHistoryStore _store;

  Future<HistoryPage> call(
    ClubContext club,
    String athleteId, {
    DateTime? before,
    int limit = defaultHistoryPageSize,
  }) async {
    ensureCanReadHistory(club, await _store.athleteUserId(club.clubId, athleteId));
    final found = await _store.sessionsBefore(club.clubId, athleteId, before: before, limit: limit);
    if (found.isEmpty) return const HistoryPage();

    // A full page may have cut its oldest date: bring the rest of that date so no session falls between pages.
    final sessions = {for (final s in found) s.id: s};
    DateTime? next;
    if (found.length >= limit) {
      next = found.map((s) => s.date).reduce((a, b) => a.isBefore(b) ? a : b);
      for (final s in await _store.sessionsOn(club.clubId, athleteId, next)) {
        sessions[s.id] = s;
      }
    }
    final ordered = sessions.values.toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        final byCreation = b.auditoria.creadoEn.compareTo(a.auditoria.creadoEn);
        return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
      });

    final plans = await _store.plans(club.clubId, {for (final s in ordered) s.planId});
    final marks = <String, List<RecordMark>>{};
    for (final r in await _store.records(club.clubId, athleteId, [for (final s in ordered) s.id])) {
      (marks[r.sessionId] ??= []).add(r.mark);
    }
    return HistoryPage(
      entries: [
        for (final s in ordered) historyEntryOf(s, plans[s.planId], marks[s.id] ?? const []),
      ],
      next: next,
    );
  }
}
