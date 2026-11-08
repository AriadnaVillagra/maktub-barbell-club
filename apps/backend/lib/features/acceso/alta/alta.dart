import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// A person to seed. The real emails never live in the repo (it is public): they come from the
/// script's configuration (see `tool/alta.dart`).
class UsuarioAlta {
  const UsuarioAlta({required this.email, required this.nombre});

  final String email;
  final String nombre;
}

/// What a run created, for the script's output.
class ResultadoAlta {
  final creados = <String>[];
  final existentes = <String>[];
}

/// Idempotent seeding (design.md 3.5, D6): the Maktub club, and per user their personal club
/// (`clubPersonalId`), memberships (coach + atleta) and athlete in both clubs. Then the Maktub group
/// (E6.2, D14): one group with every seeded user's athlete of the Maktub club as a member.
///
/// Every document is looked up by its natural key and only inserted if missing; nothing existing
/// is modified, so running it twice leaves the database identical.
class AltaInicial {
  AltaInicial(this._db, {DateTime Function()? ahora, String Function()? nuevoId})
    : _ahora = ahora ?? DateTime.now,
      _nuevoId = nuevoId ?? (() => ObjectId().oid);

  static const nombreClubMaktub = 'Maktub';

  final Db _db;
  final DateTime Function() _ahora;
  final String Function() _nuevoId;

  Future<ResultadoAlta> ejecutar(List<UsuarioAlta> usuarios) async {
    if (usuarios.isEmpty) throw ArgumentError('Hace falta al menos un usuario.');
    final emails = usuarios.map((u) => normalizarEmail(u.email)).toList();
    if (emails.toSet().length != emails.length) {
      throw ArgumentError('Hay emails repetidos.');
    }
    final r = ResultadoAlta();
    await asegurarIndices(_db);

    final usuariosCol = _db.collection(Colecciones.usuarios);
    // Resolve (or reserve) user ids first: audit fields point at them.
    final ids = <String, String>{};
    final clubPersonalIds = <String, String>{};
    for (final u in usuarios) {
      final email = normalizarEmail(u.email);
      final doc = await usuariosCol.findOne(where.eq('email', email));
      ids[email] = doc == null ? _nuevoId() : '${doc['_id']}';
      clubPersonalIds[email] = doc == null ? _nuevoId() : '${doc['clubPersonalId']}';
    }

    final maktubId = await _clubMaktub(r, creadoPor: ids[emails.first]!);

    final athleteIdsInMaktub = <String>[];
    for (final u in usuarios) {
      final email = normalizarEmail(u.email);
      final id = ids[email]!;
      final personalId = clubPersonalIds[email]!;
      final auditoria = Auditoria.nueva(id, ahora: _ahora());

      await _insertarSiFalta(
        r,
        Colecciones.clubes,
        {'_id': personalId},
        Club(
          id: personalId,
          nombre: u.nombre,
          tipo: TipoClub.personal,
          auditoria: auditoria,
        ).toJson(),
        'club personal de ${u.nombre}',
      );
      await _insertarSiFalta(
        r,
        Colecciones.usuarios,
        {'email': email},
        Usuario(
          id: id,
          email: email,
          nombre: u.nombre,
          emailVerificado: true,
          clubPersonalId: personalId,
          metodos: const {MetodoIngreso.google},
        ).toJson()..['auditoria'] = auditoria.toJson(),
        'usuario ${u.nombre}',
        id: id,
      );
      for (final clubId in [maktubId, personalId]) {
        final athleteId = await _membresiaYAtleta(r, clubId, id, u.nombre, auditoria, maktubId: maktubId);
        if (clubId == maktubId) athleteIdsInMaktub.add(athleteId);
      }
    }
    await _group(
      r,
      maktubId,
      usuarios.map((u) => u.nombre).join(' y '),
      athleteIdsInMaktub,
      Auditoria.nueva(ids[emails.first]!, ahora: _ahora()),
    );
    return r;
  }

  Future<String> _clubMaktub(ResultadoAlta r, {required String creadoPor}) async {
    final col = _db.collection(Colecciones.clubes);
    final existente = await col.findOne(
      where.eq('tipo', TipoClub.club.cable).eq('nombre', nombreClubMaktub),
    );
    if (existente != null) {
      r.existentes.add('club $nombreClubMaktub');
      return '${existente['_id']}';
    }
    final id = _nuevoId();
    await col.insertOne(
      aDocumento(
        Club(
          id: id,
          nombre: nombreClubMaktub,
          tipo: TipoClub.club,
          auditoria: Auditoria.nueva(creadoPor, ahora: _ahora()),
        ).toJson(),
      ),
    );
    r.creados.add('club $nombreClubMaktub');
    return id;
  }

  /// The group is keyed by (`clubId`, `nombre`). An existing one is left as it is, members included.
  Future<void> _group(
    ResultadoAlta r,
    String clubId,
    String name,
    List<String> memberIds,
    Auditoria auditoria,
  ) => _insertarSiFalta(
    r,
    Colecciones.grupos,
    {'clubId': clubId, 'nombre': name},
    AthleteGroup(
      id: _nuevoId(),
      clubId: clubId,
      name: name,
      memberIds: memberIds,
      auditoria: auditoria,
    ).toJson(),
    'grupo $name en $clubId',
  );

  /// Returns the id of the athlete document (existing or new).
  Future<String> _membresiaYAtleta(
    ResultadoAlta r,
    String clubId,
    String usuarioId,
    String nombre,
    Auditoria auditoria, {
    required String maktubId,
  }) async {
    final clave = {'clubId': clubId, 'usuarioId': usuarioId};
    final ahora = _ahora().toUtc();
    await _insertarSiFalta(
      r,
      Colecciones.membresias,
      clave,
      Membresia(
        id: _nuevoId(),
        clubId: clubId,
        usuarioId: usuarioId,
        roles: {Rol.coach, Rol.atleta, if (clubId == maktubId) Rol.adminClub},
        estado: EstadoMembresia.activa,
        desde: ahora,
        auditoria: auditoria,
      ).toJson(),
      'membresía de $nombre en $clubId',
    );
    final existingAthlete = await _db
        .collection(Colecciones.atletas)
        .findOne(where.eq('clubId', clubId).eq('usuarioId', usuarioId));
    final athleteId = existingAthlete == null ? _nuevoId() : '${existingAthlete['_id']}';
    await _insertarSiFalta(
      r,
      Colecciones.atletas,
      clave,
      Atleta(
        id: athleteId,
        clubId: clubId,
        usuarioId: usuarioId,
        nombreVisible: nombre,
        auditoria: auditoria,
      ).toJson(),
      'atleta $nombre en $clubId',
      id: athleteId,
    );
    return athleteId;
  }

  Future<void> _insertarSiFalta(
    ResultadoAlta r,
    String coleccion,
    Map<String, dynamic> clave,
    Json json,
    String descripcion, {
    String? id,
  }) async {
    final col = _db.collection(coleccion);
    SelectorBuilder selector() {
      final s = where;
      clave.forEach(s.eq);
      return s;
    }

    if (await col.findOne(selector()) != null) {
      r.existentes.add(descripcion);
      return;
    }
    await col.insertOne(aDocumento(json, id: id));
    r.creados.add(descripcion);
  }
}
