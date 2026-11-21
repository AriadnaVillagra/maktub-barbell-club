import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// A request as the backend keeps it: with the Google account that proved its email.
typedef StoredClubRequest = ({ClubRequest request, String? googleSub});

abstract interface class ApproveClubRequestStore {
  /// The platform's request with [requestId], or null.
  Future<StoredClubRequest?> find(String requestId);

  /// Marks the request approved with [clubId] as the club to create, only while it is pending, in one atomic
  /// write. Returns the request as it is afterwards (approved by this call or reviewed before), null if missing.
  Future<StoredClubRequest?> markApproved(
    String requestId, {
    required String clubId,
    required String reviewedBy,
    required DateTime reviewedAt,
  });

  /// Inserts [user] (with [googleSub] linked) unless a user with that email exists, and returns the user that
  /// has the email afterwards.
  Future<Usuario> insertUserIfMissing(Usuario user, {String? googleSub, required Auditoria auditoria});

  /// Each inserts only if missing: a club by id, a membership and an athlete by (`clubId`, `usuarioId`).
  Future<void> ensureClub(Club club);
  Future<void> ensureMembership(Membresia membership);
  Future<void> ensureAthlete(Atleta athlete);
}

class MongoApproveClubRequestStore implements ApproveClubRequestStore {
  MongoApproveClubRequestStore(this._db);

  final Db _db;

  DbCollection get _requests => _db.collection(Colecciones.clubRequests);

  static StoredClubRequest _stored(Map<String, dynamic> doc) =>
      (request: ClubRequest.fromJson(desdeDocumento(doc)), googleSub: doc['googleSub'] as String?);

  @override
  Future<StoredClubRequest?> find(String requestId) async {
    final doc = await _requests.findOne({'_id': requestId, 'clubId': clubPlataforma});
    return doc == null ? null : _stored(doc);
  }

  @override
  Future<StoredClubRequest?> markApproved(
    String requestId, {
    required String clubId,
    required String reviewedBy,
    required DateTime reviewedAt,
  }) async {
    final when = reviewedAt.toUtc().toIso8601String();
    final result = await _requests.modernFindAndModify(
      query: {'_id': requestId, 'clubId': clubPlataforma, 'estado': ClubRequestStatus.pending.cable},
      update: {
        r'$set': {
          'estado': ClubRequestStatus.approved.cable,
          'clubCreadoId': clubId,
          'revisadoPor': reviewedBy,
          'revisadoEn': when,
          'auditoria.modificadoPor': reviewedBy,
          'auditoria.modificadoEn': when,
        },
      },
      returnNew: true,
    );
    final doc = result.value;
    return doc != null ? _stored(doc) : find(requestId);
  }

  @override
  Future<Usuario> insertUserIfMissing(Usuario user, {String? googleSub, required Auditoria auditoria}) async {
    final users = _db.collection(Colecciones.usuarios);
    final existing = await users.findOne({'email': user.email});
    if (existing != null) return Usuario.fromJson(desdeDocumento(existing));
    final result = await users.insertOne({
      ...aDocumento(user.toJson()),
      'googleSub': ?googleSub,
      'auditoria': auditoria.toJson(),
    });
    if (result.isSuccess) return user;
    // Someone else created the user in between (the email is unique): that one stands.
    final winner = await users.findOne({'email': user.email});
    if (winner == null) throw StateError('No se pudo crear el usuario: ${result.writeError?.errmsg}');
    return Usuario.fromJson(desdeDocumento(winner));
  }

  @override
  Future<void> ensureClub(Club club) async {
    final clubs = _db.collection(Colecciones.clubes);
    if (await clubs.findOne({'_id': club.id}) == null) await _insertIgnoringDuplicate(clubs, club.toJson());
  }

  @override
  Future<void> ensureMembership(Membresia membership) => _ensureByClubAndUser(
    _db.collection(Colecciones.membresias),
    membership.clubId,
    membership.usuarioId,
    membership.toJson(),
  );

  @override
  Future<void> ensureAthlete(Atleta athlete) =>
      _ensureByClubAndUser(_db.collection(Colecciones.atletas), athlete.clubId, athlete.usuarioId, athlete.toJson());

  Future<void> _ensureByClubAndUser(DbCollection col, String clubId, String userId, Json json) async {
    if (await col.findOne({'clubId': clubId, 'usuarioId': userId}) == null) await _insertIgnoringDuplicate(col, json);
  }

  /// A duplicate key means a concurrent approval inserted it first, which is what was wanted.
  static Future<void> _insertIgnoringDuplicate(DbCollection col, Json json) async {
    final result = await col.insertOne(aDocumento(json));
    if (!result.isSuccess && result.writeError?.code != 11000) {
      throw StateError('No se pudo guardar en ${col.collectionName}: ${result.writeError?.errmsg}');
    }
  }
}
