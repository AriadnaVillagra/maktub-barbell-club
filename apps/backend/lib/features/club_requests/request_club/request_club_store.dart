import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class RequestClubStore {
  /// Whether a user with [email] (normalized) exists.
  Future<bool> userExists(String email);

  /// The state of the latest request of [email], or null if it never sent one.
  Future<ClubRequestStatus?> latestStatus(String email);

  /// Inserts [request] (pending) with the Google account that proved the email. `false` if the email already
  /// has a pending request (duplicate key on the unique index).
  Future<bool> insertPending(ClubRequest request, {required String googleSub});
}

class MongoRequestClubStore implements RequestClubStore {
  MongoRequestClubStore(this._db);

  final Db _db;

  DbCollection get _requests => _db.collection(Colecciones.clubRequests);

  @override
  Future<bool> userExists(String email) async =>
      await _db.collection(Colecciones.usuarios).findOne(where.eq('email', email).fields(['_id'])) != null;

  @override
  Future<ClubRequestStatus?> latestStatus(String email) async {
    final doc = await _requests.findOne(
      where.eq('clubId', clubPlataforma).eq('email', email).sortBy('auditoria.creadoEn', descending: true).fields(['estado']),
    );
    return doc == null ? null : ClubRequestStatus.fromWire(doc['estado']);
  }

  @override
  Future<bool> insertPending(ClubRequest request, {required String googleSub}) async {
    final result = await _requests.insertOne({...aDocumento(request.toJson()), 'googleSub': googleSub});
    if (result.isSuccess) return true;
    if (result.writeError?.code == 11000) return false;
    throw StateError('No se pudo guardar el pedido: ${result.writeError?.errmsg}');
  }
}
