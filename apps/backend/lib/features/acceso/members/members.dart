import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'members_store.dart';

/// `GET /clubes/{clubId}/miembros` → `{miembros: [{usuarioId, nombre, email, roles}]}`.
/// Needs `gestionarMiembros`.
Future<Response> listMembersEndpoint(RequestContext context, {MembersStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.gestionarMiembros);
  final members = await (store ?? MongoMembersStore(context.read<Db>())).activeMembers(club.clubId);
  return Response.json(body: {'miembros': [for (final m in members) m.toJson()]});
}

/// `POST /clubes/{clubId}/miembros` `{email, nombre, roles}` → the member. Needs `gestionarMiembros`.
Future<Response> registerMemberEndpoint(RequestContext context, {MembersStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.gestionarMiembros);
  final member = await RegisterMember(
    store ?? MongoMembersStore(context.read<Db>()),
  )(club, await leerCuerpoJson(context.request));
  return Response.json(body: member.toJson());
}

/// Gives a person their roles in the club. Google sign-in only admits registered users, so a new email
/// gets a user and a personal club here (with [nombre]); an existing member just gets the new roles,
/// which is also how a coach becomes a club admin.
class RegisterMember {
  RegisterMember(this._store, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? DateTime.now,
      _newId = newId ?? (() => ObjectId().oid);

  final MembersStore _store;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<ClubMember> call(ClubContext club, Json body) async {
    final email = normalizarEmail('${body['email'] ?? ''}');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const ErrorDeSolicitud('El email no es válido.');
    }
    final roles = _roles(body['roles']);
    final user = await _store.findUser(email) ?? await _createUser(club, email, body['nombre']);

    final current = await _store.findMembership(club.clubId, user.id);
    if (current != null && current.activa) await _rejectOrphaning(club, current, roles);

    final now = _now().toUtc();
    final audit = current?.auditoria.modificada(club.userId, ahora: now) ?? Auditoria.nueva(club.userId, ahora: now);
    final membership = Membresia(
      id: current?.id ?? _newId(),
      clubId: club.clubId,
      usuarioId: user.id,
      roles: roles,
      estado: EstadoMembresia.activa,
      desde: current?.activa == true ? current!.desde : now,
      auditoria: audit,
    );
    await _store.saveMembership(membership);
    if (roles.contains(Rol.atleta)) {
      await _store.ensureAthlete(
        Atleta(id: _newId(), clubId: club.clubId, usuarioId: user.id, nombreVisible: user.nombre, auditoria: audit),
      );
    }
    return ClubMember(membership: membership, name: user.nombre, email: user.email);
  }

  Set<Rol> _roles(Object? raw) {
    final Set<Rol> roles;
    try {
      roles = rolesDeCable(raw);
    } on Object {
      throw const ErrorDeSolicitud('Los roles no son válidos.');
    }
    if (roles.isEmpty) throw const ErrorDeSolicitud('Elegí al menos un rol.');
    return roles;
  }

  Future<Usuario> _createUser(ClubContext club, String email, Object? rawName) async {
    final name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) throw const ErrorDeSolicitud('Ese email no está registrado: indicá el nombre.');
    final now = _now().toUtc();
    final audit = Auditoria.nueva(club.userId, ahora: now);
    final id = _newId();
    final personalId = _newId();
    final user = Usuario(
      id: id,
      email: email,
      nombre: name,
      emailVerificado: true,
      clubPersonalId: personalId,
      metodos: const {MetodoIngreso.google},
    );
    await _store.createUser(
      user,
      Club(id: personalId, nombre: name, tipo: TipoClub.personal, auditoria: audit),
      Membresia(
        id: _newId(),
        clubId: personalId,
        usuarioId: id,
        roles: const {Rol.coach, Rol.atleta},
        estado: EstadoMembresia.activa,
        desde: now,
        auditoria: audit,
      ),
      Atleta(id: _newId(), clubId: personalId, usuarioId: id, nombreVisible: name, auditoria: audit),
    );
    return user;
  }

  Future<void> _rejectOrphaning(ClubContext club, Membresia current, Set<Rol> roles) async {
    final all = [for (final m in await _store.activeMembers(club.clubId)) m.membership];
    if (current.roles.contains(Rol.adminClub) && dejaSinAdmin(all, current.usuarioId, roles)) {
      throw const ErrorDeSolicitud('El club tiene que conservar al menos un administrador.');
    }
    if (current.roles.contains(Rol.coach) && dejaSinCoach(all, current.usuarioId, roles)) {
      throw const ErrorDeSolicitud('El club tiene que conservar al menos un coach.');
    }
  }
}
