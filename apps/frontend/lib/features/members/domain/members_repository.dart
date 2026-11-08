import 'package:maktub_core/maktub_core.dart';

/// An active member of the club.
class ClubMember {
  const ClubMember({required this.userId, required this.name, required this.email, required this.roles});

  final String userId;
  final String name;
  final String email;
  final Set<Rol> roles;

  factory ClubMember.fromJson(Json j) => ClubMember(
    userId: '${j['usuarioId']}',
    name: '${j['nombre']}',
    email: '${j['email']}',
    roles: rolesDeCable(j['roles']),
  );
}

abstract interface class MembersRepository {
  Future<List<ClubMember>> members(String clubId);

  /// Registers [email] with [roles], or changes the roles of whoever already has that email.
  /// [name] is required only for an email that isn't registered yet.
  Future<ClubMember> register(String clubId, {required String email, required String name, required Set<Rol> roles});
}
