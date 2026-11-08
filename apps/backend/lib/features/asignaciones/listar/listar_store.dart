import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "list assignments" slice reads.
abstract interface class ListAssignmentsStore {
  /// The assignments of [clubId] and of no other club; only those of [groupId] when it is given.
  Future<List<Assignment>> assignments(String clubId, {String? groupId});
}

class MongoListAssignmentsStore implements ListAssignmentsStore {
  MongoListAssignmentsStore(this._db);

  final Db _db;

  @override
  Future<List<Assignment>> assignments(String clubId, {String? groupId}) async {
    final docs = await _db.collection(Colecciones.asignaciones).find({
      'clubId': clubId,
      'grupoId': ?groupId,
    }).toList();
    return [for (final d in docs) Assignment.fromJson(desdeDocumento(d))];
  }
}
