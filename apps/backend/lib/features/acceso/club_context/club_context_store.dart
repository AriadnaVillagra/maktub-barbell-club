import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the club context reads: the user's active membership in one club, and that club's type.
abstract interface class ClubContextStore {
  /// The membership of [userId] in [clubId] with state `activa`, or null.
  Future<Membresia?> activeMembership({required String clubId, required String userId});

  Future<TipoClub?> clubType(String clubId);
}

class MongoClubContextStore implements ClubContextStore {
  MongoClubContextStore(this._db);

  final Db _db;

  @override
  Future<Membresia?> activeMembership({required String clubId, required String userId}) async {
    final doc = await _db.collection(Colecciones.membresias).findOne({
      'clubId': clubId,
      'usuarioId': userId,
      'estado': EstadoMembresia.activa.cable,
    });
    return doc == null ? null : Membresia.fromJson(desdeDocumento(doc));
  }

  @override
  Future<TipoClub?> clubType(String clubId) async {
    final doc = await _db.collection(Colecciones.clubes).findOne(where.eq('_id', clubId).fields(['tipo']));
    return doc == null ? null : TipoClub.deCable(doc['tipo']);
  }
}
