import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/domain/live_session_sync.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

import 'live_fakes.dart';

SetWrite _mark(String athlete, int set, {double? kg}) {
  final w = SetWrite.of(
    null,
    athleteId: athlete,
    blockIndex: 0,
    prescriptionIndex: 0,
    setIndex: set,
    adjustment: 0,
  ).markedDone();
  return kg == null ? w : w.edited(manualKg: kg, reps: null);
}

/// Lets the fake channel's futures and streams run.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

class _Device {
  _Device(
    FakeLiveServer server, {
    int since = 0,
    bool Function(Object)? isFinal,
  }) {
    sync = LiveSessionSync(
      channel: FakeLiveChannel(server),
      clubId: 'c1',
      sessionId: 's1',
      since: since,
      onChanges: received.addAll,
      onConnected: () => connected++,
      isFinal: isFinal ?? (_) => false,
      backoff: const [Duration.zero],
    );
  }

  late final LiveSessionSync sync;
  final received = <SessionChange>[];
  var connected = 0;

  /// The sets this device has seen marked, by athlete and set.
  Set<(String, int)> get marked => {
    for (final c in received)
      if (c.record case final r? when r.done) (r.athleteId, r.setIndex),
  };
}

void main() {
  late FakeLiveServer server;
  final devices = <_Device>[];

  _Device device({int since = 0, bool Function(Object)? isFinal}) {
    final d = _Device(server, since: since, isFinal: isFinal);
    devices.add(d);
    return d;
  }

  setUp(() => server = FakeLiveServer());
  tearDown(() async {
    for (final d in devices) {
      await d.sync.stop();
    }
    devices.clear();
  });

  test('a set marked on one device arrives on the other', () async {
    final a = device()..sync.start();
    final b = device()..sync.start();
    await _settle();
    expect(a.sync.status, LiveStatus.live);
    expect(b.sync.status, LiveStatus.live);

    server.write(_mark('ari', 0));
    await _settle();

    expect(b.marked, {('ari', 0)});
    expect(a.marked, {('ari', 0)}, reason: 'the writer gets its own change');
    expect(b.sync.lastSeen, 1);
  });

  test('connects first and then resyncs what was written before', () async {
    server.write(_mark('ari', 0));
    server.write(_mark('andi', 0));
    final b = device()..sync.start();
    await _settle();

    expect(server.resyncsFrom, [0]);
    expect(b.marked, {('ari', 0), ('andi', 0)});
    expect(b.sync.lastSeen, 2);
    expect(b.connected, 1);
  });

  test('a cut reconnects by itself and loses no marks', () async {
    final b = device()..sync.start();
    await _settle();
    server.write(_mark('ari', 0));
    await _settle();

    server.drop(); // Cloud Run's hourly close, or the network
    server.down = true;
    await _settle();
    expect(b.sync.status, LiveStatus.reconnecting);
    // Marked on another device while this one had no channel: the server published to nobody. Synchronous, so it
    // happens before the next attempt to reconnect.
    server.down = false;
    server.write(_mark('ari', 1));
    server.write(_mark('andi', 0));
    expect(server.openConnections, 0);
    await _settle();

    expect(b.sync.status, LiveStatus.live);
    expect(b.marked, {('ari', 0), ('ari', 1), ('andi', 0)});
    expect(server.resyncsFrom.last, 1, reason: 'resyncs from the last seen');
    expect(b.connected, greaterThanOrEqualTo(2));
    expect(server.openConnections, 1);
  });

  test('a reload resyncs from the number it had', () async {
    server.write(_mark('ari', 0));
    server.write(_mark('ari', 1));
    server.write(_mark('andi', 0));
    // The app reloaded: the session it opened already had the first two changes.
    final b = device(since: 2)..sync.start();
    await _settle();

    expect(server.resyncsFrom, [2]);
    expect(b.marked, {('andi', 0)});
    expect(b.sync.lastSeen, 3);
  });

  test('numbers can skip without counting as a loss', () async {
    server.write(_mark('ari', 0));
    server.sequence = 7; // a change to something this device does not follow
    final b = device(since: 1)..sync.start();
    await _settle();
    server.write(_mark('ari', 1));
    await _settle();

    expect(b.marked, {('ari', 1)});
    expect(b.sync.lastSeen, 8);
    expect(server.connects, 1, reason: 'no reconnect over a gap');
  });

  test('while the channel does not answer it keeps trying', () async {
    server.down = true;
    final b = device()..sync.start();
    await _settle();
    expect(b.sync.status, isNot(LiveStatus.live));
    expect(server.connects, greaterThan(1));

    server.down = false;
    await _settle();
    expect(b.sync.status, LiveStatus.live);
  });

  test('stops when the server refuses the session for good', () async {
    final refusing = _RefusingServer();
    final sync = LiveSessionSync(
      channel: FakeLiveChannel(refusing),
      clubId: 'c1',
      sessionId: 's1',
      since: 0,
      onChanges: (_) {},
      isFinal: (e) => e is ErrorDeApi && e.estado == 404,
      backoff: const [Duration.zero],
    )..start();
    await _settle();

    expect(sync.status, LiveStatus.stopped);
    expect(refusing.connects, 1);
  });

  test('stopping closes the connection and receives nothing more', () async {
    final b = device()..sync.start();
    await _settle();
    await b.sync.stop();
    await _settle();
    server.write(_mark('ari', 0));
    await _settle();

    expect(b.received, isEmpty);
    expect(server.openConnections, 0);
  });

  group('applyChanges', () {
    LiveSession live(List<SetRecord> records) =>
        LiveSession(session: server.session, records: records);

    test('a resync older than what arrived does not take it back', () {
      final first = server.write(_mark('ari', 0, kg: 90));
      final second = server.write(_mark('ari', 0, kg: 95));

      final result = applyChanges(live([second]), [
        SessionChange.ofRecord(first.sequence!, first),
      ]);

      expect(result.records.single.kg, 95);
    });

    test('adds a set it did not have and replaces an older one', () {
      final a = server.write(_mark('ari', 0, kg: 90));
      final b = server.write(_mark('andi', 0));
      final a2 = server.write(_mark('ari', 0, kg: 92.5));

      final result = applyChanges(live([a]), [
        SessionChange.ofRecord(b.sequence!, b),
        SessionChange.ofRecord(a2.sequence!, a2),
      ]);

      expect(result.records.map((r) => (r.athleteId, r.kg)), [
        ('ari', 92.5),
        ('andi', 100),
      ]);
    });

    test('applies a change of the session itself (note, present)', () {
      final note = Session.fromJson({
        ...server.session.toJson(),
        'nota': 'Buen día',
        'secuenciaSesion': 3,
      });

      final result = applyChanges(live(const []), [
        SessionChange.ofSession(3, note),
      ]);

      expect(result.session.note, 'Buen día');
    });
  });
}

/// A server that answers 404 to the ticket: the session is not the user's.
class _RefusingServer extends FakeLiveServer {
  @override
  Future<Never> connect() async {
    connects++;
    throw const ErrorDeApi('Sesión no encontrada.', estado: 404);
  }
}
