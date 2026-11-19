import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the club context reads: the user's active membership in one club, and that club's type.
abstract interface class ClubContextStore {
  /// The membership of [userId] in [clubId] with state `activa`, or null.
  Future<Membresia?> activeMembership({required String clubId, required String userId});

  Future<TipoClub?> clubType(String clubId);

  Future<bool> isPlatformAdmin(String userId);
}

/// One store per request (`requireClub` makes it). [activeMembership] brings the club's type and the user's platform
/// admin flag in the same round trip, and [clubType] and [isPlatformAdmin] answer from it: every request under
/// `/clubes/{id}` resolves its context with one query instead of three (2026-11-19: the server asks the database one
/// query at a time, so each one counts).
class MongoClubContextStore implements ClubContextStore {
  MongoClubContextStore(this._db);

  final Db _db;

  /// What the last [activeMembership] brought along, for that club and that user.
  ({String clubId, String userId, TipoClub? type, bool admin})? _brought;

  @override
  Future<Membresia?> activeMembership({required String clubId, required String userId}) async {
    final docs = await _db.collection(Colecciones.membresias).modernAggregate([
      {
        r'$match': {'clubId': clubId, 'usuarioId': userId, 'estado': EstadoMembresia.activa.cable},
      },
      {r'$limit': 1},
      {
        r'$lookup': {
          'from': Colecciones.clubes,
          'localField': 'clubId',
          'foreignField': '_id',
          'pipeline': [
            {
              r'$project': {'tipo': 1},
            },
          ],
          'as': '_club',
        },
      },
      {
        r'$lookup': {
          'from': Colecciones.usuarios,
          'localField': 'usuarioId',
          'foreignField': '_id',
          'pipeline': [
            {
              r'$project': {'esAdminPlataforma': 1},
            },
          ],
          'as': '_usuario',
        },
      },
    ]).toList();
    if (docs.isEmpty) return null;
    final doc = docs.single;
    final club = (doc.remove('_club') as List).firstOrNull as Map?;
    final user = (doc.remove('_usuario') as List).firstOrNull as Map?;
    _brought = (
      clubId: clubId,
      userId: userId,
      type: club == null ? null : TipoClub.deCable(club['tipo']),
      admin: user?['esAdminPlataforma'] == true,
    );
    return Membresia.fromJson(desdeDocumento(doc));
  }

  @override
  Future<TipoClub?> clubType(String clubId) async {
    final brought = _brought;
    if (brought != null && brought.clubId == clubId) return brought.type;
    final doc = await _db.collection(Colecciones.clubes).findOne(where.eq('_id', clubId).fields(['tipo']));
    return doc == null ? null : TipoClub.deCable(doc['tipo']);
  }

  @override
  Future<bool> isPlatformAdmin(String userId) async {
    final brought = _brought;
    if (brought != null && brought.userId == userId) return brought.admin;
    final doc = await _db.collection(Colecciones.usuarios).findOne(where.eq('_id', userId).fields(['esAdminPlataforma']));
    return doc?['esAdminPlataforma'] == true;
  }
}
