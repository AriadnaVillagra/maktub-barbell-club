import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/domain/me.dart';
import 'package:maktub_frontend/features/access/domain/me_repository.dart';

Club club(String id, String name, TipoClub type) =>
    Club(id: id, nombre: name, tipo: type, auditoria: Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 7)));

/// A user with a personal club and one membership per entry of [memberships].
Me meWith(List<(Club, Set<Rol>)> memberships, {bool isPlatformAdmin = false}) {
  final personal = club('personal-1', 'Mi entrenamiento', TipoClub.personal);
  return Me(
    user: Usuario(
      id: 'u1',
      email: 'ari@example.com',
      nombre: 'Ari',
      emailVerificado: true,
      clubPersonalId: personal.id,
    ),
    personalClub: personal,
    clubs: [for (final (c, roles) in memberships) ClubAccess(club: c, roles: roles)],
    isPlatformAdmin: isPlatformAdmin,
  );
}

class FakeMeRepository implements MeRepository {
  FakeMeRepository(this.me);

  final Me me;

  @override
  Future<Me> fetch() async => me;
}
