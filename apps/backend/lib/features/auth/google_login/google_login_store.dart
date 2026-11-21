import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What Google login needs from a user: who it is and which Google account is linked, if any.
typedef GoogleLoginUser = ({String id, String? googleSub});

abstract interface class GoogleLoginStore {
  /// The user with this email, already normalized (`normalizarEmail`), or `null` if there is none.
  Future<GoogleLoginUser?> findByEmail(String email);

  /// Links [sub] to the user with [email] only if no Google account is linked yet, in one atomic
  /// write. `false` means another account got linked first.
  Future<bool> linkGoogleSub(String email, String sub);

  /// The state of the latest club request of [email] (normalized), or `null` if it never sent one.
  Future<ClubRequestStatus?> latestClubRequestStatus(String email);
}

class MongoGoogleLoginStore implements GoogleLoginStore {
  MongoGoogleLoginStore(this._db);

  final Db _db;

  DbCollection get _users => _db.collection(Colecciones.usuarios);

  @override
  Future<GoogleLoginUser?> findByEmail(String email) async {
    final doc = await _users.findOne(where.eq('email', email).fields(['_id', 'googleSub']));
    if (doc == null) return null;
    return (id: desdeDocumento(doc)['id'] as String, googleSub: doc['googleSub'] as String?);
  }

  @override
  Future<bool> linkGoogleSub(String email, String sub) async {
    final result = await _users.updateOne(
      {'email': email, 'googleSub': null},
      {
        r'$set': {'googleSub': sub, 'emailVerificado': true},
        r'$addToSet': {'metodos': MetodoIngreso.google.cable},
      },
    );
    return result.nModified == 1;
  }

  @override
  Future<ClubRequestStatus?> latestClubRequestStatus(String email) async {
    final doc = await _db.collection(Colecciones.clubRequests).findOne(
      where.eq('clubId', clubPlataforma).eq('email', email).sortBy('auditoria.creadoEn', descending: true).fields(['estado']),
    );
    return doc == null ? null : ClubRequestStatus.fromWire(doc['estado']);
  }
}
