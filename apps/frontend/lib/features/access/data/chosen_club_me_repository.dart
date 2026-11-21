import '../domain/chosen_club_store.dart';
import '../domain/me.dart';
import '../domain/me_repository.dart';

/// `GET /me` working in the club the user picked on this device ([Me.withChosenClub]).
class ChosenClubMeRepository implements MeRepository {
  ChosenClubMeRepository(this._inner, this._store);

  final MeRepository _inner;
  final ChosenClubStore _store;

  @override
  Future<Me> fetch() async {
    final me = await _inner.fetch();
    return me.withChosenClub(await _store.read(me.user.id));
  }
}
