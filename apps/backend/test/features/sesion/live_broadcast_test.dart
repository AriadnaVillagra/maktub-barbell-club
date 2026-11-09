import 'dart:async';

import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:test/test.dart';

void main() {
  group('inOrder', () {
    test('changes of one session run one after the other', () async {
      final broadcast = MemoryLiveBroadcast();
      final first = Completer<void>();
      final log = <String>[];

      final a = broadcast.inOrder('s1', () async {
        log.add('a starts');
        await first.future;
        log.add('a ends');
      });
      final b = broadcast.inOrder('s1', () async => log.add('b'));
      await pumpEventQueue();
      first.complete();
      await Future.wait([a, b]);

      expect(log, ['a starts', 'a ends', 'b']);
    });

    test('another session does not wait', () async {
      final broadcast = MemoryLiveBroadcast();
      final blocked = Completer<void>();

      final a = broadcast.inOrder('s1', () => blocked.future);

      await broadcast
          .inOrder('s2', () async {})
          .timeout(const Duration(seconds: 5));
      blocked.complete();
      await a;
    });

    test(
      'a failure reaches its caller and the next change still runs',
      () async {
        final broadcast = MemoryLiveBroadcast();

        final failed = broadcast.inOrder<void>('s1', () async {
          throw StateError('boom');
        });
        final next = broadcast.inOrder('s1', () async => 'ok');

        await expectLater(failed, throwsStateError);
        expect(await next, 'ok');
      },
    );
  });
}
