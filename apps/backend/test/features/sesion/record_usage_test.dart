import 'dart:io';

import 'package:maktub_backend/features/sesion/record_usage/record_usage.dart';
import 'package:maktub_backend/features/sesion/record_usage/record_usage_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

class _FakeStore implements RecordUsageStore {
  _FakeStore(this.records);

  final List<({String clubId, String exerciseId})> records;

  @override
  Future<bool> exerciseInRecords(String? clubId, String exerciseId) async =>
      records.any(
        (r) =>
            (clubId == null || r.clubId == clubId) &&
            r.exerciseId == exerciseId,
      );
}

void _cases(
  Future<RecordUsageStore> Function(
    List<({String clubId, String exerciseId})> records,
  )
  build,
) {
  Future<bool> used(
    List<({String clubId, String exerciseId})> records,
    String clubId,
    String id,
  ) async => RecordExerciseUsage(await build(records)).isUsed(clubId, id);

  test('an exercise with a record is in use', () async {
    expect(
      await used([(clubId: 'club-a', exerciseId: 'squat')], 'club-a', 'squat'),
      isTrue,
    );
  });

  test('an exercise without records is not in use', () async {
    expect(
      await used([(clubId: 'club-a', exerciseId: 'squat')], 'club-a', 'snatch'),
      isFalse,
    );
    expect(await used([], 'club-a', 'squat'), isFalse);
  });

  test('records of another club do not count for a club exercise', () async {
    expect(
      await used([(clubId: 'club-b', exerciseId: 'squat')], 'club-a', 'squat'),
      isFalse,
    );
  });

  test('a platform exercise counts records of every club', () async {
    expect(
      await used(
        [(clubId: 'club-b', exerciseId: 'squat')],
        clubPlataforma,
        'squat',
      ),
      isTrue,
    );
  });
}

void main() {
  group('fake store', () {
    _cases((records) async => _FakeStore(records));
  });

  group('Mongo store', () {
    Db? db;
    final name = 'maktub_test_e7_4_${DateTime.now().microsecondsSinceEpoch}';

    setUpAll(() async {
      try {
        final base =
            Platform.environment['TEST_MONGO_URL'] ??
            'mongodb://localhost:27017';
        db = await abrirMongo('$base/$name');
      } on Object catch (e) {
        stderr.writeln('mongo: $e');
        db = null;
      }
    });

    tearDownAll(() async {
      await db?.drop();
      await db?.close();
    });

    var n = 0;
    _cases((records) async {
      final d = db;
      if (d == null) {
        markTestSkipped('MongoDB not available');
        return _FakeStore(records);
      }
      final coll = d.collection(Colecciones.registros);
      await coll.remove({});
      for (final r in records) {
        await coll.insertOne({
          '_id': 'r${n++}',
          'clubId': r.clubId,
          'ejercicioId': r.exerciseId,
        });
      }
      return MongoRecordUsageStore(d);
    });
  });
}
