import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "record a set" slice reads and writes. Every method carries the club id.
abstract interface class RecordSetStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The published version of the plan [planId] of [clubId] (never the draft), or null if it has none.
  Future<PublishedPlan?> publishedPlan(String clubId, String planId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The exercises [clubId] can see, by id: the default catalog and its own. Archived ones included.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// The RM and other references of [athleteId] for [exerciseId] (the full history).
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    String exerciseId,
  );

  /// The work factors of [athleteId] for [exerciseId] (the full history).
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    String exerciseId,
  );

  /// The fixed weight of [athleteId] for [exerciseId], or null if the coach loaded none.
  Future<FixedWeight?> fixedWeight(
    String clubId,
    String athleteId,
    String exerciseId,
  );

  /// The club's equipment, or null if it never saved one.
  Future<Equipo?> equipment(String clubId);

  /// Atomically writes [record] under its key (club, session, athlete, block, prescription and set) and returns
  /// what is stored. If the key exists, its id and creation audit stay and everything else becomes [record]'s,
  /// including the optional fields [record] no longer has. Touches that one document only.
  Future<SetRecord> upsert(SetRecord record);
}

class MongoRecordSetStore implements RecordSetStore {
  MongoRecordSetStore(this._db);

  final Db _db;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc)).published;
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async {
    final docs = await _db.collection(Colecciones.ejercicios).find({
      'clubId': {
        r'$in': [clubPlataforma, clubId],
      },
    }).toList();
    return {
      for (final d in docs)
        '${d['_id']}': Exercise.fromJson(desdeDocumento(d)),
    };
  }

  Future<List<Json>> _history(
    String collection,
    String clubId,
    String athleteId,
    String exerciseId,
  ) async {
    final docs = await _db.collection(collection).find({
      'clubId': clubId,
      'atletaId': athleteId,
      'ejercicioId': exerciseId,
    }).toList();
    return [for (final d in docs) desdeDocumento(d)];
  }

  @override
  Future<List<Reference>> references(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => [
    for (final j in await _history(
      Colecciones.referencias,
      clubId,
      athleteId,
      exerciseId,
    ))
      Reference.fromJson(j),
  ];

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => [
    for (final j in await _history(
      Colecciones.factoresTrabajo,
      clubId,
      athleteId,
      exerciseId,
    ))
      WorkFactor.fromJson(j),
  ];

  @override
  Future<FixedWeight?> fixedWeight(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async {
    final doc = await _db.collection(Colecciones.kilajesFijos).findOne({
      'clubId': clubId,
      'atletaId': athleteId,
      'ejercicioId': exerciseId,
    });
    return doc == null ? null : FixedWeight.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Equipo?> equipment(String clubId) async {
    final doc = await _db.collection(Colecciones.equipos).findOne({
      '_id': clubId,
      'clubId': clubId,
    });
    return doc == null ? null : Equipo.fromJson(desdeDocumento(doc));
  }

  @override
  Future<SetRecord> upsert(SetRecord record) async {
    final doc = aDocumento(record.toJson());
    final filter = <String, dynamic>{
      for (final key in _keyFields) key: doc[key],
    };
    final set = <String, dynamic>{
      for (final e in doc.entries)
        if (e.key != '_id' && e.key != 'auditoria' && !filter.containsKey(e.key))
          e.key: e.value,
    };
    final auditoria = record.auditoria.toJson();
    final stored = await upsertByUniqueKey(
      _db.collection(Colecciones.registros),
      filter,
      {
        r'$set': {
          ...set,
          'auditoria.modificadoPor': auditoria['modificadoPor'],
          'auditoria.modificadoEn': auditoria['modificadoEn'],
        },
        r'$setOnInsert': {
          '_id': doc['_id'],
          'auditoria.creadoPor': auditoria['creadoPor'],
          'auditoria.creadoEn': auditoria['creadoEn'],
        },
        r'$unset': {
          for (final field in _optionalFields)
            if (!doc.containsKey(field)) field: '',
        },
      },
    );
    return SetRecord.fromJson(desdeDocumento(stored));
  }
}

const _keyFields = [
  'clubId',
  'sesionId',
  'atletaId',
  'bloque',
  'prescripcion',
  'serie',
];

/// Keys `SetRecord.toJson` leaves out when they have no value. A rewrite that no longer has one must clear it.
const _optionalFields = [
  'kilos',
  'reps',
  'segundos',
  'distanciaM',
  'calorias',
  'referenciaId',
  'referenciaValor',
  'factor',
  'pctPlan',
  'pctReal',
  'rpe',
  'kilosManual',
];
