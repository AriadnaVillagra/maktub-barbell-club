import '../../../core/red/cliente_api.dart';
import '../domain/me.dart';
import '../domain/me_repository.dart';

class HttpMeRepository implements MeRepository {
  HttpMeRepository(this._client);

  final ClienteApi _client;

  @override
  Future<Me> fetch() async => Me.fromJson(await _client.get('/me'));
}
