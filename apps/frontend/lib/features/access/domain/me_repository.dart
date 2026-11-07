import 'me.dart';

abstract interface class MeRepository {
  /// `GET /me`.
  Future<Me> fetch();
}
