import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/athlete_adjustments.dart';
import '../domain/block_time_write.dart';
import '../domain/live_session_sync.dart' show sameSet;
import '../domain/session_repository.dart';
import '../domain/set_write.dart';
import 'cached_proposed_days_repository.dart';

/// The session with the device's copy (E7.15): the last state seen of each session opened here, kept up to date
/// with what this device writes, and its kilos, either those last seen or those the preload saved for its date.
///
/// Without signal, opening a session this device already opened gives the saved one; a session never opened here
/// still needs signal (E7.16 will queue the opening). Writes always go to the server (the queue retries them).
///
/// Day adjustment without signal: the server resolves the kilos with the athlete's factor, which the athlete never
/// receives, so the app does not recompute them. Without signal only the adjustments already seen (the neutral one
/// is always preloaded) show kilos; any other says so.
class CachedSessionRepository implements SessionRepository {
  CachedSessionRepository(this._remote, this._reads, this._proposedDays);

  final SessionRepository _remote;
  final LocalCopyReads _reads;
  final CachedProposedDaysRepository _proposedDays;

  static String _sessionKey(
    String clubId,
    String assignmentId,
    DateTime date,
    int week,
    int day,
  ) => copyKey(['session', clubId, assignmentId, aIsoFecha(date), week, day]);

  static String _indexKey(String clubId, String sessionId) =>
      copyKey(['sessionIndex', clubId, sessionId]);

  static String _adjustmentKey(AthleteAdjustments a) {
    final exercises = a.exercises.entries.toList()
      ..sort((x, y) => x.key.compareTo(y.key));
    return [a.session, for (final e in exercises) '${e.key}:${e.value}']
        .join(',');
  }

  static bool _isNeutral(AthleteAdjustments a) =>
      a.session == Ajuste.neutro &&
      a.exercises.values.every((v) => v == Ajuste.neutro);

  static const offlineAdjustmentMessage =
      'Sin señal no se puede calcular el ajuste del día: los kilos con ajuste los calcula el servidor. '
      'Volvé a 100 % para ver los kilos guardados, o esperá a que vuelva la señal.';

  static const _neverOpened =
      'Sin señal: esta sesión no se abrió antes en este dispositivo. Se abre cuando vuelva la señal.';

  static const _noLoads =
      'Sin señal y sin kilos guardados para este día. Se cargan cuando vuelva la señal.';

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    final live = await _reads.read(
      _sessionKey(clubId, assignmentId, date, week, day),
      () => _remote.open(
        clubId,
        assignmentId: assignmentId,
        date: date,
        week: week,
        day: day,
        presentAthleteIds: presentAthleteIds,
      ),
      encode: liveSessionToJson,
      decode: (d) => liveSessionFromJson((d as Map).cast<String, dynamic>()),
      missing: _neverOpened,
    );
    await _index(live.session);
    return live;
  }

  /// Keeps [live] as the last state seen of its session, so it opens without signal. E7.16 hands the session it
  /// opens on the device here.
  Future<void> remember(LiveSession live) async {
    final s = live.session;
    await _reads.save(
      _sessionKey(s.clubId, s.assignmentId, s.date, s.week, s.day),
      live,
      liveSessionToJson,
    );
    await _index(s);
  }

  Future<void> _index(Session s) => _reads.store.write(
    _indexKey(s.clubId, s.id),
    _sessionKey(s.clubId, s.assignmentId, s.date, s.week, s.day),
  );

  /// The last state saved of [sessionId] and the key it is under, or null.
  Future<(LiveSession, String)?> _saved(String clubId, String sessionId) async {
    final index = await _reads.store.read(_indexKey(clubId, sessionId));
    final key = index?.data;
    if (key is! String) return null;
    final copy = await _reads.store.read(key);
    if (copy == null) return null;
    try {
      return (
        liveSessionFromJson((copy.data as Map).cast<String, dynamic>()),
        key,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    final key = copyKey([
      'loads',
      clubId,
      sessionId,
      athleteId,
      _adjustmentKey(adjustments),
    ]);
    final List<ProposedSet> sets;
    try {
      sets = await _remote.proposedLoads(
        clubId,
        sessionId,
        athleteId,
        adjustments,
      );
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return _savedLoads(key, clubId, sessionId, athleteId, adjustments);
    }
    _reads.reporter.servedFresh();
    await _reads.save(key, sets, _setsToJson);
    return sets;
  }

  Future<List<ProposedSet>> _savedLoads(
    String key,
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    final copy = await _reads.store.read(key);
    if (copy != null) {
      try {
        final sets = _setsFromJson(copy.data);
        _reads.reporter.servedFromCopy(copy.savedAt);
        return sets;
      } catch (_) {
        // An unreadable copy: fall through to the preloaded kilos.
      }
    }
    if (!_isNeutral(adjustments)) {
      throw const NoLocalCopy(offlineAdjustmentMessage);
    }
    final s = (await _saved(clubId, sessionId))?.$1.session;
    final preloaded = s == null
        ? null
        : await _proposedDays.savedSets(
            clubId,
            s.assignmentId,
            date: s.date,
            cycle: s.cycle,
            week: s.week,
            day: s.day,
            athleteId: athleteId,
          );
    if (preloaded == null) throw const NoLocalCopy(_noLoads);
    return preloaded;
  }

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    final stored = await _remote.recordSet(clubId, sessionId, write);
    await _update(clubId, sessionId, (live) {
      final kept = [
        for (final r in live.records)
          if (!sameSet(r, stored)) r,
      ];
      return LiveSession(session: live.session, records: [...kept, stored]);
    });
    return stored;
  }

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) => _remote.recordBlockTime(clubId, sessionId, timeId, write);

  @override
  Future<Session> saveSessionNote(
    String clubId,
    String sessionId,
    String note,
  ) async {
    final session = await _remote.saveSessionNote(clubId, sessionId, note);
    await _update(
      clubId,
      sessionId,
      (live) => LiveSession(session: session, records: live.records),
    );
    return session;
  }

  Future<void> _update(
    String clubId,
    String sessionId,
    LiveSession Function(LiveSession) change,
  ) async {
    final saved = await _saved(clubId, sessionId);
    if (saved == null) return;
    await _reads.save(saved.$2, change(saved.$1), liveSessionToJson);
  }
}

Json liveSessionToJson(LiveSession live) => {
  'sesion': live.session.toJson(),
  'registros': [for (final r in live.records) r.toJson()],
};

LiveSession liveSessionFromJson(Json j) => LiveSession(
  session: Session.fromJson((j['sesion'] as Map).cast<String, dynamic>()),
  records: [
    for (final r in j['registros'] as List)
      SetRecord.fromJson((r as Map).cast<String, dynamic>()),
  ],
);

List<Json> _setsToJson(List<ProposedSet> sets) => [
  for (final s in sets) s.toJson(),
];

List<ProposedSet> _setsFromJson(Object? d) => [
  for (final s in d as List)
    ProposedSet.fromJson((s as Map).cast<String, dynamic>()),
];
