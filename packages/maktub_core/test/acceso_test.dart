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
    const ambos = {Rol.coach, Rol.atleta};

    test('el atleta ve, registra y ve sus reportes, nada más', () {
      final permitidas = {for (final a in Accion.values) if (puede(atleta, a, TipoClub.club)) a};
      expect(permitidas, {Accion.verCatalogoYPlanes, Accion.registrar, Accion.verReportesPropios});
    });

    test('el coach planifica, pero no toca el catálogo del club ni los miembros sin ser admin del club', () {
      expect(puede(coach, Accion.editarCatalogoClub, TipoClub.club), isFalse);
      expect(puede(coach, Accion.gestionarMiembros, TipoClub.club), isFalse);
      expect(puede({Rol.coach, Rol.adminClub}, Accion.editarCatalogoClub, TipoClub.club), isTrue);
      expect(puede({Rol.coach, Rol.adminClub}, Accion.gestionarMiembros, TipoClub.club), isTrue);
      expect(puede({Rol.adminClub}, Accion.editarCatalogoClub, TipoClub.personal), isFalse);
    });

    test('lo default solo lo cambia el admin de plataforma; lo del club, el admin del club', () {
      final cat = Category(id: 'x', clubId: clubPlataforma, name: 'x', auditoria: Auditoria.nueva('u', ahora: DateTime.utc(2026)));
      final propia = Category(id: 'y', clubId: 'c1', name: 'y', auditoria: Auditoria.nueva('u', ahora: DateTime.utc(2026)));
      const admin = {Rol.coach, Rol.adminClub};
      expect(puedeEscribirCatalogo(cat, admin, TipoClub.club), isFalse);
      expect(puedeEscribirCatalogo(cat, const {Rol.coach}, TipoClub.club, esAdminPlataforma: true), isTrue);
      expect(puedeEscribirCatalogo(propia, admin, TipoClub.club), isTrue);
      expect(puedeEscribirCatalogo(propia, const {Rol.coach}, TipoClub.club, esAdminPlataforma: true), isFalse);
    });

    test('el coach planifica y gestiona su trabajo, pero no sigue planes por defecto ni edita plataforma', () {
      for (final a in [Accion.planificar, Accion.editarReferencias, Accion.verReportesDeTodos, Accion.registrar]) {
        expect(puede(coach, a, TipoClub.club), isTrue, reason: a.name);
      }
      expect(puede(coach, Accion.seguirPlanPorDefecto, TipoClub.club), isFalse);
      expect(puede(coach, Accion.editarPlataforma, TipoClub.club), isFalse);
    });

    test('en el club personal no se planifica aunque la membresía tenga coach', () {
      expect(puede(ambos, Accion.planificar, TipoClub.personal), isFalse);
      expect(puede(ambos, Accion.gestionarMiembros, TipoClub.personal), isFalse);
      expect(puede(ambos, Accion.verReportesDeTodos, TipoClub.personal), isFalse);
      expect(puede(ambos, Accion.seguirPlanPorDefecto, TipoClub.personal), isTrue);
      expect(puede(ambos, Accion.editarReferencias, TipoClub.personal), isTrue);
    });

    test('sin roles no se puede nada dentro de un club', () {
      for (final a in Accion.values) {
        expect(puede(const {}, a, TipoClub.club), isFalse, reason: a.name);
      }
    });

    test('editar plataforma depende solo de la marca de administrador', () {
      expect(puede(const {}, Accion.editarPlataforma, TipoClub.personal, esAdminPlataforma: true), isTrue);
      expect(puede(ambos, Accion.editarPlataforma, TipoClub.club), isFalse);
      expect(puede(atleta, Accion.planificar, TipoClub.club, esAdminPlataforma: true), isFalse);
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
