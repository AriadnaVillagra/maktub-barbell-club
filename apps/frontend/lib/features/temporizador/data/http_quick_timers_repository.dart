import '../../../core/red/cliente_api.dart';
import '../domain/quick_timers_repository.dart';

class HttpQuickTimersRepository implements QuickTimersRepository {
  HttpQuickTimersRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId) => '/clubes/${Uri.encodeComponent(clubId)}/temporizadores-a-mano';

  static List<String> _ids(Map<String, dynamic> json) => [
    for (final id in (json['temporizadorIds'] as List? ?? const [])) '$id',
  ];

  @override
  Future<List<String>> ids(String clubId) async => _ids(await _client.get(_path(clubId)));

  @override
  Future<List<String>> save(String clubId, List<String> ids) async =>
      _ids(await _client.put(_path(clubId), {'temporizadorIds': ids}));
}
