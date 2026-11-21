import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class RejectClubRequestStore {
  /// Marks the platform's request rejected only while it is pending, in one atomic write. Returns the request
  /// as it is afterwards (rejected by this call or reviewed before), null if missing.
  Future<ClubRequest?> markRejected(String requestId, {required String reviewedBy, required DateTime reviewedAt});
}

class MongoRejectClubRequestStore implements RejectClubRequestStore {
  MongoRejectClubRequestStore(this._db);

  final Db _db;

  @override
  Future<ClubRequest?> markRejected(String requestId, {required String reviewedBy, required DateTime reviewedAt}) async {
    final requests = _db.collection(Colecciones.clubRequests);
    final when = reviewedAt.toUtc().toIso8601String();
    final result = await requests.modernFindAndModify(
      query: {'_id': requestId, 'clubId': clubPlataforma, 'estado': ClubRequestStatus.pending.cable},
      update: {
        r'$set': {
          'estado': ClubRequestStatus.rejected.cable,
          'revisadoPor': reviewedBy,
          'revisadoEn': when,
          'auditoria.modificadoPor': reviewedBy,
          'auditoria.modificadoEn': when,
        },
      },
      returnNew: true,
    );
    final doc = result.value ?? await requests.findOne({'_id': requestId, 'clubId': clubPlataforma});
    return doc == null ? null : ClubRequest.fromJson(desdeDocumento(doc));
  }
}
