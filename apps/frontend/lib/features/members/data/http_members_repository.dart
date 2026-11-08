import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/members_repository.dart';

class HttpMembersRepository implements MembersRepository {
  HttpMembersRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId) => '/clubes/${Uri.encodeComponent(clubId)}/miembros';

  @override
  Future<List<ClubMember>> members(String clubId) async {
    final json = await _client.get(_path(clubId));
    return [
      for (final m in (json['miembros'] as List? ?? const []))
        ClubMember.fromJson((m as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<ClubMember> register(
    String clubId, {
    required String email,
    required String name,
    required Set<Rol> roles,
  }) async => ClubMember.fromJson(
    await _client.post(_path(clubId), cuerpo: {'email': email, 'nombre': name, 'roles': rolesACable(roles)}),
  );
}
