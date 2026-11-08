import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// An active member of a club, with what the list shows.
class ClubMember {
  const ClubMember({required this.membership, required this.name, required this.email});

  final Membresia membership;
  final String name;
  final String email;

  Json toJson() => {
    'usuarioId': membership.usuarioId,
    'nombre': name,
    'email': email,
    'roles': rolesACable(membership.roles),
  };
}

abstract interface class MembersStore {
  Future<List<ClubMember>> activeMembers(String clubId);

  /// The user with that normalized email, or null.
  Future<Usuario?> findUser(String email);

  /// The membership of [userId] in [clubId], active or ended.
  Future<Membresia?> findMembership(String clubId, String userId);

  /// Stores a new user with their personal club, membership and athlete.
  Future<void> createUser(Usuario user, Club personalClub, Membresia personalMembership, Atleta personalAthlete);

  Future<void> saveMembership(Membresia membership);

  /// Creates the athlete if that user has none in the club.
  Future<void> ensureAthlete(Atleta athlete);
}

class MongoMembersStore implements MembersStore {
  MongoMembersStore(this._db);

  final Db _db;

  @override
  Future<List<ClubMember>> activeMembers(String clubId) async {
    final docs = await _db.collection(Colecciones.membresias).find({
      'clubId': clubId,
      'estado': EstadoMembresia.activa.cable,
    }).toList();
    final memberships = [for (final d in docs) Membresia.fromJson(desdeDocumento(d))];
    final users = await _db.collection(Colecciones.usuarios).find({
      '_id': {r'$in': [for (final m in memberships) m.usuarioId]},
    }).toList();
    final byId = {for (final u in users) '${u['_id']}': u};
    return [
      for (final m in memberships)
        ClubMember(
          membership: m,
          name: '${byId[m.usuarioId]?['nombre'] ?? ''}',
          email: '${byId[m.usuarioId]?['email'] ?? ''}',
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<Usuario?> findUser(String email) async {
    final doc = await _db.collection(Colecciones.usuarios).findOne(where.eq('email', email));
    return doc == null ? null : Usuario.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Membresia?> findMembership(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.membresias).findOne({'clubId': clubId, 'usuarioId': userId});
    return doc == null ? null : Membresia.fromJson(desdeDocumento(doc));
  }

  @override
  Future<void> createUser(
    Usuario user,
    Club personalClub,
    Membresia personalMembership,
    Atleta personalAthlete,
  ) async {
    await _db.collection(Colecciones.clubes).insertOne(aDocumento(personalClub.toJson()));
    await _db
        .collection(Colecciones.usuarios)
        .insertOne(aDocumento(user.toJson()..['auditoria'] = personalClub.auditoria.toJson()));
    await _db.collection(Colecciones.membresias).insertOne(aDocumento(personalMembership.toJson()));
    await _db.collection(Colecciones.atletas).insertOne(aDocumento(personalAthlete.toJson()));
  }

  @override
  Future<void> saveMembership(Membresia membership) async {
    await _db.collection(Colecciones.membresias).replaceOne(
      {'_id': membership.id, 'clubId': membership.clubId},
      aDocumento(membership.toJson()),
      upsert: true,
    );
  }

  @override
  Future<void> ensureAthlete(Atleta athlete) async {
    final col = _db.collection(Colecciones.atletas);
    if (await col.findOne({'clubId': athlete.clubId, 'usuarioId': athlete.usuarioId}) == null) {
      await col.insertOne(aDocumento(athlete.toJson()));
    }
  }
}
