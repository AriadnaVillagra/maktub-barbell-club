import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _auditoria = Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 7, 10));

Membresia _membresia(String usuarioId, Set<Rol> roles, {EstadoMembresia estado = EstadoMembresia.activa}) => Membresia(
      id: 'm-$usuarioId',
      clubId: 'c1',
      usuarioId: usuarioId,
      roles: roles,
      estado: estado,
      desde: DateTime.utc(2026, 11, 7),
      auditoria: _auditoria,
    );

Invitacion _invitacion({int? usosMaximos, int usos = 0, bool revocada = false}) => Invitacion(
      id: 'i1',
      clubId: 'c1',
      codigo: 'ABC123',
      roles: {Rol.atleta},
      vence: DateTime.utc(2026, 11, 14),
      usosMaximos: usosMaximos,
      usos: usos,
      revocada: revocada,
      auditoria: _auditoria,
    );

void main() {
  group('modelos', () {
    test('Usuario normaliza el email y no expone credenciales', () {
      final u = Usuario(
        id: 'u1',
        email: '  Ari@Gmail.COM ',
        nombre: 'Ari',
        emailVerificado: true,
        clubPersonalId: 'p1',
        metodos: {MetodoIngreso.contrasena, MetodoIngreso.google},
      );
      final json = u.toJson();
      final copia = Usuario.fromJson(json);

      expect(u.email, 'ari@gmail.com');
      expect(json['metodos'], ['google', 'contrasena']);
      expect(copia.metodos, {MetodoIngreso.google, MetodoIngreso.contrasena});
      expect((copia.emailVerificado, copia.esAdminPlataforma, copia.clubPersonalId), (true, false, 'p1'));
    });

    test('Club, Membresia, Invitacion y Atleta viajan ida y vuelta por JSON', () {
      final club = Club.fromJson(Club(id: 'c1', nombre: 'Maktub', tipo: TipoClub.club, auditoria: _auditoria).toJson());
      expect((club.nombre, club.tipo, club.esPersonal, club.auditoria.creadoPor), ('Maktub', TipoClub.club, false, 'u1'));

      final m = Membresia.fromJson(_membresia('u2', {Rol.atleta, Rol.coach})
          .copiarCon(estado: EstadoMembresia.terminada, hasta: DateTime.utc(2026, 12, 1, 8))
          .toJson());
      expect(m.roles, {Rol.coach, Rol.atleta});
      expect((m.estado, m.hasta, m.activa), (EstadoMembresia.terminada, DateTime.utc(2026, 12, 1, 8), false));
      expect(_membresia('u2', {Rol.atleta, Rol.coach}).toJson()['roles'], ['coach', 'atleta']);
      expect(_membresia('u2', {Rol.atleta}).toJson().containsKey('hasta'), isFalse);

      final i = Invitacion.fromJson(_invitacion(usosMaximos: 5, usos: 2).toJson());
      expect(i.roles, {Rol.atleta});
      expect((i.codigo, i.vence, i.usosMaximos, i.usos, i.revocada), ('ABC123', DateTime.utc(2026, 11, 14), 5, 2, false));
      expect(Invitacion.fromJson(_invitacion().toJson()).usosMaximos, isNull);

      final a = Atleta.fromJson(
          Atleta(id: 'a1', clubId: 'c1', usuarioId: 'u2', nombreVisible: 'Andi', auditoria: _auditoria).toJson());
      expect((a.clubId, a.usuarioId, a.nombreVisible), ('c1', 'u2', 'Andi'));
    });

    test('un rol desconocido se rechaza', () {
      expect(() => rolesDeCable(['coach', 'dueño']), throwsFormatException);
    });
  });

  group('estado de una invitación', () {
    final antes = DateTime.utc(2026, 11, 10);

    test('vigente mientras no venza, no se revoque ni se agote', () {
      expect(_invitacion().estadoEn(antes), EstadoInvitacion.vigente);
      expect(_invitacion(usosMaximos: 3, usos: 2).estadoEn(antes), EstadoInvitacion.vigente);
    });

    test('vence en el instante exacto de vencimiento', () {
      expect(_invitacion().estadoEn(DateTime.utc(2026, 11, 14)), EstadoInvitacion.vencida);
    });

    test('agotada al llegar a los usos máximos', () {
      expect(_invitacion(usosMaximos: 3, usos: 3).estadoEn(antes), EstadoInvitacion.agotada);
    });

    test('revocada pesa más que vencida y agotada', () {
      final i = _invitacion(usosMaximos: 1, usos: 1, revocada: true);
      expect(i.estadoEn(DateTime.utc(2027)), EstadoInvitacion.revocada);
    });
  });

  group('matriz de permisos', () {
    const atleta = {Rol.atleta};
    const coach = {Rol.coach};
    const admin = {Rol.adminClub};
    const ambos = {Rol.coach, Rol.atleta};
    Set<Accion> permitidas(Set<Rol> roles, {TipoClub tipo = TipoClub.club, bool plataforma = false}) => {
      for (final a in Accion.values)
        if (puede(roles, a, tipo, esAdminPlataforma: plataforma)) a,
    };

    test('jerarquía: cada nivel puede todo lo que pueden los de abajo, y algo más', () {
      for (final nivel in PermissionLevel.values.skip(1)) {
        final abajo = PermissionLevel.values[nivel.index - 1];
        expect(actionsOf(nivel).containsAll(actionsOf(abajo)), isTrue, reason: nivel.name);
        expect(actionsOf(nivel).length, greaterThan(actionsOf(abajo).length), reason: nivel.name);
      }
    });

    test('cada acción de club la agrega un solo nivel', () {
      final agregadas = [for (final n in PermissionLevel.values) ...n.adds];
      expect(agregadas.toSet().length, agregadas.length);
      expect({...agregadas, Accion.seguirPlanPorDefecto}, Accion.values.toSet());
    });

    test('el nivel lo da el rol más alto; la marca de plataforma, por encima de todo', () {
      expect(PermissionLevel.of(atleta), PermissionLevel.athlete);
      expect(PermissionLevel.of(ambos), PermissionLevel.coach);
      expect(PermissionLevel.of(admin), PermissionLevel.clubAdmin);
      expect(PermissionLevel.of({Rol.atleta, Rol.adminClub}), PermissionLevel.clubAdmin);
      expect(PermissionLevel.of(const {}, isPlatformAdmin: true), PermissionLevel.platform);
      expect(PermissionLevel.of(atleta, isPlatformAdmin: true), PermissionLevel.platform);
      expect(PermissionLevel.of(const {}), isNull);
    });

    test('en un club, lo que puede cada rol es lo de su nivel', () {
      expect(permitidas(atleta), actionsOf(PermissionLevel.athlete));
      expect(permitidas(coach), actionsOf(PermissionLevel.coach));
      expect(permitidas(ambos), actionsOf(PermissionLevel.coach));
      expect(permitidas(admin), actionsOf(PermissionLevel.clubAdmin));
      expect(permitidas(const {}, plataforma: true), actionsOf(PermissionLevel.platform));
    });

    test('el atleta solo ve, registra y ve lo suyo', () {
      expect(permitidas(atleta), {Accion.verCatalogoYPlanes, Accion.registrar, Accion.verReportesPropios});
    });

    test('el coach: planes, asignaciones, catálogo del club (ejercicios, categorías, temporizadores) y atletas', () {
      for (final a in [
        Accion.planificar,
        Accion.deletePlan,
        Accion.editarCatalogoClub,
        Accion.editarReferencias,
        Accion.verReportesDeTodos,
        Accion.registrar,
      ]) {
        expect(puede(coach, a, TipoClub.club), isTrue, reason: a.name);
      }
      expect(puede(coach, Accion.editarEquipo, TipoClub.club), isFalse);
      expect(puede(coach, Accion.gestionarMiembros, TipoClub.club), isFalse);
      expect(puede(coach, Accion.editarPlataforma, TipoClub.club), isFalse);
    });

    test('el admin del club puede todo en su club: también planes, asignaciones, equipo y miembros', () {
      for (final a in [
        Accion.planificar,
        Accion.deletePlan,
        Accion.editarReferencias,
        Accion.editarCatalogoClub,
        Accion.editarEquipo,
        Accion.gestionarMiembros,
        Accion.verReportesDeTodos,
        Accion.registrar,
      ]) {
        expect(puede(admin, a, TipoClub.club), isTrue, reason: a.name);
      }
      expect(puede(admin, Accion.editarPlataforma, TipoClub.club), isFalse);
      expect(puede(admin, Accion.reviewClubRequests, TipoClub.club), isFalse);
    });

    test('el admin de plataforma puede todo en cualquier club, aunque no sea miembro', () {
      for (final a in actionsOf(PermissionLevel.clubAdmin)) {
        expect(puede(const {}, a, TipoClub.club, esAdminPlataforma: true), isTrue, reason: a.name);
      }
      expect(puede(atleta, Accion.planificar, TipoClub.club, esAdminPlataforma: true), isTrue);
    });

    test('en el club personal no se planifica aunque la membresía tenga coach o la marca de plataforma', () {
      for (final roles in [ambos, {Rol.adminClub, Rol.coach, Rol.atleta}]) {
        expect(permitidas(roles, tipo: TipoClub.personal), {
          Accion.verCatalogoYPlanes,
          Accion.registrar,
          Accion.verReportesPropios,
          Accion.editarReferencias,
          Accion.seguirPlanPorDefecto,
        });
      }
      expect(puede(const {}, Accion.planificar, TipoClub.personal, esAdminPlataforma: true), isFalse);
      expect(puede(const {}, Accion.registrar, TipoClub.personal, esAdminPlataforma: true), isTrue);
    });

    test('sin roles ni marca de plataforma no se puede nada', () {
      for (final tipo in TipoClub.values) {
        expect(permitidas(const {}, tipo: tipo), isEmpty, reason: tipo.name);
      }
    });

    test('las acciones de plataforma dependen solo de la marca, nunca de los roles', () {
      for (final a in platformActions) {
        expect(puede(const {}, a, TipoClub.personal, esAdminPlataforma: true), isTrue, reason: a.name);
        expect(puede({Rol.adminClub, Rol.coach}, a, TipoClub.club), isFalse, reason: a.name);
      }
    });

    test('catálogo: lo default solo el admin de plataforma; lo del club, coach, admin del club o plataforma', () {
      final auditoria = Auditoria.nueva('u', ahora: DateTime.utc(2026));
      final base = Category(id: 'x', clubId: clubPlataforma, name: 'x', auditoria: auditoria);
      final propia = Category(id: 'y', clubId: 'c1', name: 'y', auditoria: auditoria);
      expect(puedeEscribirCatalogo(base, {Rol.adminClub, Rol.coach}, TipoClub.club), isFalse);
      expect(puedeEscribirCatalogo(base, coach, TipoClub.club, esAdminPlataforma: true), isTrue);
      expect(puedeEscribirCatalogo(propia, coach, TipoClub.club), isTrue);
      expect(puedeEscribirCatalogo(propia, admin, TipoClub.club), isTrue);
      expect(puedeEscribirCatalogo(propia, const {}, TipoClub.club, esAdminPlataforma: true), isTrue);
      expect(puedeEscribirCatalogo(propia, atleta, TipoClub.club), isFalse);
      expect(puedeEscribirCatalogo(propia, ambos, TipoClub.personal), isFalse);
    });
  });

  group('último coach', () {
    test('no se puede quitar ni hacer salir al único coach activo', () {
      final membresias = [_membresia('u1', {Rol.coach, Rol.atleta}), _membresia('u2', {Rol.atleta})];
      expect(dejaSinCoach(membresias, 'u1', const {}), isTrue);
      expect(dejaSinCoach(membresias, 'u1', {Rol.atleta}), isTrue);
      expect(dejaSinCoach(membresias, 'u1', {Rol.coach}), isFalse);
      expect(dejaSinCoach(membresias, 'u2', const {}), isFalse);
    });

    test('con otro coach activo sí se puede; un coach con membresía terminada no cuenta', () {
      final conOtro = [_membresia('u1', {Rol.coach}), _membresia('u2', {Rol.coach})];
      expect(dejaSinCoach(conOtro, 'u1', const {}), isFalse);

      final otroTerminado = [_membresia('u1', {Rol.coach}), _membresia('u2', {Rol.coach}, estado: EstadoMembresia.terminada)];
      expect(dejaSinCoach(otroTerminado, 'u1', const {}), isTrue);
    });
  });
}
