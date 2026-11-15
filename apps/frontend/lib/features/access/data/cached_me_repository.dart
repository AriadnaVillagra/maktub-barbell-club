import '../../../core/offline/local_copy.dart';
import '../domain/me.dart';
import '../domain/me_repository.dart';

/// `GET /me` with the device's copy (E7.15): without signal the app still knows who the user is and their club, so
/// the saved token is enough to get in.
class CachedMeRepository implements MeRepository {
  CachedMeRepository(this._remote, this._reads);

  final MeRepository _remote;
  final LocalCopyReads _reads;

  static const key = 'me';

  @override
  Future<Me> fetch() => _reads.read(
    key,
    _remote.fetch,
    encode: (me) => me.toJson(),
    decode: (d) => Me.fromJson((d as Map).cast<String, dynamic>()),
  );
}
