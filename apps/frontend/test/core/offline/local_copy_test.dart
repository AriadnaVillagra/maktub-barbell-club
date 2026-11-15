import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/core/offline/local_copy.dart';
import 'package:maktub_frontend/core/offline/shared_preferences_local_copy_store.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Reporter implements LocalCopyReporter {
  final events = <Object>[];

  @override
  void servedFresh() => events.add('fresh');

  @override
  void servedFromCopy(DateTime savedAt) => events.add(savedAt);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var now = DateTime.utc(2026, 11, 14, 9, 30);
  SharedPreferencesLocalCopyStore store() =>
      SharedPreferencesLocalCopyStore(now: () => now);

  group('LocalCopyReads', () {
    test('keeps what the server answers and serves it without signal, saying from when', () async {
      final reporter = _Reporter();
      final reads = LocalCopyReads(store(), reporter);
      Future<int> read(Future<int> Function() fetch) =>
          reads.read('k', fetch, encode: (v) => v, decode: (d) => d as int);

      expect(await read(() async => 7), 7);
      expect(
        await read(() async => throw const ErrorDeApi('sin conexión')),
        7,
      );
      expect(reporter.events, ['fresh', now]);
    });

    test('the server down counts as without signal; a refusal on purpose does not', () async {
      final reads = LocalCopyReads(store(), _Reporter());
      Future<int> read(Future<int> Function() fetch) =>
          reads.read('k', fetch, encode: (v) => v, decode: (d) => d as int);
      await read(() async => 7);

      expect(
        await read(() async => throw const ErrorDeApi('caído', estado: 503)),
        7,
      );
      await expectLater(
        read(() async => throw const ErrorDeApi('prohibido', estado: 403)),
        throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'estado', 403)),
      );
    });

    test('without a copy it throws NoLocalCopy with the message given', () async {
      final reads = LocalCopyReads(store(), _Reporter());

      await expectLater(
        reads.read<int>(
          'nada',
          () async => throw const ErrorDeApi('sin conexión'),
          encode: (v) => v,
          decode: (d) => d as int,
          missing: 'No hay nada guardado.',
        ),
        throwsA(
          isA<NoLocalCopy>().having((e) => e.mensaje, 'mensaje', 'No hay nada guardado.'),
        ),
      );
    });

    test('a copy saved as null reads back as null, not as missing', () async {
      final reads = LocalCopyReads(store(), _Reporter());
      Future<int?> read(Future<int?> Function() fetch) =>
          reads.read('k', fetch, encode: (v) => v, decode: (d) => d as int?);
      await read(() async => null);

      expect(await read(() async => throw const ErrorDeApi('sin conexión')), isNull);
    });
  });

  group('SharedPreferencesLocalCopyStore', () {
    test('a new instance reads what an earlier one saved, as after reloading the app', () async {
      await store().write('a/1', {'x': 1});

      final copy = await store().read('a/1');

      expect(copy?.data, {'x': 1});
      expect(copy?.savedAt, now);
      expect(await store().keys('a/'), ['a/1']);
    });

    test('prune drops the copies saved before the date given', () async {
      await store().write('old', 1);
      now = now.add(const Duration(days: 20));
      await store().write('new', 2);

      await store().prune(now.subtract(const Duration(days: 14)));

      expect(await store().read('old'), isNull);
      expect((await store().read('new'))?.data, 2);
    });

    test('without storage nothing fails and nothing is kept', () async {
      final blocked = SharedPreferencesLocalCopyStore(
        preferences: () async => throw Exception('storage blocked'),
      );

      await blocked.write('k', 1);
      await blocked.prune(now);
      expect(await blocked.read('k'), isNull);
      expect(await blocked.keys(''), isEmpty);
    });
  });
}
