import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

void main() {
  group('withSafeAtlas', () {
    test('adds safeAtlas=true to an Atlas URL', () {
      expect(
        withSafeAtlas('mongodb+srv://u:p@cluster.example.net/maktub'),
        'mongodb+srv://u:p@cluster.example.net/maktub?safeAtlas=true',
      );
    });

    test('keeps the other query parameters', () {
      final url = Uri.parse(withSafeAtlas('mongodb://localhost:27017/maktub?authSource=admin'));
      expect(url.queryParameters, {'authSource': 'admin', 'safeAtlas': 'true'});
      expect(url.path, '/maktub');
    });

    test('leaves an explicit safeAtlas alone', () {
      const url = 'mongodb://localhost:27017/maktub?safeAtlas=false';
      expect(withSafeAtlas(url), url);
    });
  });

  group('MongoConnection', () {
    // A Db that was never opened reports isConnected == false, like one whose socket was reset.
    Db down() => Db('mongodb://localhost:1/maktub');

    test('opens a new connection when the current one is down', () async {
      final replacement = down();
      var opens = 0;
      final connection = MongoConnection(down(), open: () async {
        opens++;
        return replacement;
      });

      await connection.ensureOpen();

      expect(opens, 1);
      expect(connection.db, same(replacement));
    });

    test('concurrent requests share one attempt', () async {
      var opens = 0;
      final connection = MongoConnection(down(), open: () async {
        opens++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return down();
      });

      await Future.wait([for (var i = 0; i < 8; i++) connection.ensureOpen()]);

      expect(opens, 1);
    });

    test('a failed attempt is retried on the next request', () async {
      var opens = 0;
      final first = down();
      final connection = MongoConnection(first, open: () async {
        opens++;
        if (opens == 1) throw StateError('Atlas unreachable');
        return down();
      });

      await expectLater(connection.ensureOpen(), throwsStateError);
      expect(connection.db, same(first));

      await connection.ensureOpen();
      expect(opens, 2);
      expect(connection.db, isNot(same(first)));
    });
  });
}
