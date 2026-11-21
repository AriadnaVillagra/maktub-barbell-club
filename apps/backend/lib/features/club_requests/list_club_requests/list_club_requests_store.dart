import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class ListClubRequestsStore {
  /// The platform's club requests in [status] (all when null), oldest first.
  Future<List<ClubRequest>> list({ClubRequestStatus? status});
}

class MongoListClubRequestsStore implements ListClubRequestsStore {
  MongoListClubRequestsStore(this._db);

  final Db _db;

  @override
  Future<List<ClubRequest>> list({ClubRequestStatus? status}) async {
    var query = where.eq('clubId', clubPlataforma);
    if (status != null) query = query.eq('estado', status.cable);
    final docs = await _db.collection(Colecciones.clubRequests).find(query.sortBy('auditoria.creadoEn')).toList();
    return [for (final d in docs) ClubRequest.fromJson(desdeDocumento(d))];
  }
}
