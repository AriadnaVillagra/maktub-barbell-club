import 'dart:async';

import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/live_channel.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

Auditoria _audit() => Auditoria(
  creadoPor: 'u1',
  creadoEn: DateTime.utc(2026, 11, 1),
  modificadoPor: 'u1',
  modificadoEn: DateTime.utc(2026, 11, 1),
);

/// One session on a fake backend: numbers its changes like E7.6, publishes each one to every open connection (the
/// writer's included) and answers resyncs with the current state of what changed.
class FakeLiveServer {
  FakeLiveServer({this.clubId = 'c1', this.sessionId = 's1'});

  final String clubId;
  final String sessionId;
  var sequence = 0;
  final records = <(String, int, int, int), SetRecord>{};
  final _connections = <StreamController<SessionChange>>[];

  /// Without signal: opening the channel and resyncing fail as the API client reports it.
  var down = false;

  /// Set writes fail as without signal, while the channel still works.
  var writesDown = false;

  /// The channel does not answer: opening it never completes (a cold start that takes long).
  var hanging = false;

  int connects = 0;
  final resyncsFrom = <int>[];

  int get openConnections => _connections.length;

  Session get session => Session(
    id: sessionId,
    clubId: clubId,
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 3,
    week: 4,
    day: 1,
    date: DateTime.utc(2026, 11, 18),
    presentAthleteIds: const ['ari', 'andi'],
    sequence: sequence,
    auditoria: _audit(),
  );

  /// Stores what [write] leaves, as E7.3 does (computed kilos are 100 unless typed), and publishes it.
  SetRecord write(SetWrite write) {
    if (down || writesDown) {
      throw const ErrorDeApi('No se pudo conectar con el servidor.');
    }
    final key = (
      write.athleteId,
      write.blockIndex,
      write.prescriptionIndex,
      write.setIndex,
    );
    final record = records[key] = SetRecord(
      id: 'r-$key',
      clubId: clubId,
      sessionId: sessionId,
      athleteId: write.athleteId,
      exerciseId: 'sq',
      exerciseName: 'Sentadilla',
      blockIndex: write.blockIndex,
      prescriptionIndex: write.prescriptionIndex,
      setIndex: write.setIndex,
      target: const PlanSet(reps: 5, pct: 80),
      done: write.done,
      kg: write.manualKg ?? 100,
      reps: write.reps ?? 5,
      manualKg: write.manualKg != null,
      sequence: ++sequence,
      writtenBy: 'u1',
      auditoria: _audit(),
    );
    final change = SessionChange.ofRecord(sequence, record);
    for (final c in _connections) {
      c.add(change);
    }
    return record;
  }

  /// Closes every connection as Cloud Run or the network do (1006): the stream just ends.
  void drop() {
    for (final c in [..._connections]) {
      c.close();
    }
    _connections.clear();
  }

  Future<LiveConnection> connect() async {
    connects++;
    if (hanging) return Completer<LiveConnection>().future;
    if (down) throw const ErrorDeApi('No se pudo conectar con el servidor.');
    late final StreamController<SessionChange> controller;
    controller = StreamController<SessionChange>(
      onCancel: () => _connections.remove(controller),
    );
    _connections.add(controller);
    return _FakeConnection(controller);
  }

  Future<ChangesSince> changesSince(int since) async {
    resyncsFrom.add(since);
    if (down) throw const ErrorDeApi('No se pudo conectar con el servidor.');
    final changed = [
      for (final r in records.values)
        if (r.sequence! > since) SessionChange.ofRecord(r.sequence!, r),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    return ChangesSince(last: sequence, changes: changed);
  }
}

class _FakeConnection implements LiveConnection {
  _FakeConnection(this._controller);

  final StreamController<SessionChange> _controller;

  @override
  Stream<SessionChange> get changes => _controller.stream;

  @override
  Future<void> close() async {
    if (!_controller.isClosed) unawaited(_controller.close());
  }
}

/// A device's view of the [server]'s live channel.
class FakeLiveChannel implements LiveChannel {
  FakeLiveChannel(this.server);

  final FakeLiveServer server;

  @override
  Future<LiveConnection> connect(String clubId, String sessionId) =>
      server.connect();

  @override
  Future<ChangesSince> changesSince(
    String clubId,
    String sessionId,
    int since,
  ) => server.changesSince(since);
}

/// The session endpoints over the same [server], so a write is numbered and published like on the backend.
class FakeLiveSessions implements SessionRepository {
  FakeLiveSessions(this.server);

  final FakeLiveServer server;

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    if (server.down) {
      throw const ErrorDeApi('No se pudo conectar con el servidor.');
    }
    return LiveSession(
      session: server.session,
      records: server.records.values.toList(),
    );
  }

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async => server.write(write);

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async => const [];

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) async {}

  @override
  Future<Session> saveSessionNote(
    String clubId,
    String sessionId,
    String note,
  ) async => server.session;
}
