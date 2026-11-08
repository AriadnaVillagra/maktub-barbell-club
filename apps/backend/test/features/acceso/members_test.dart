import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/acceso/members/members.dart';
import 'package:maktub_backend/features/acceso/members/members_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

class _FakeStore implements MembersStore {
  final users = <String, Usuario>{};
  final memberships = <Membresia>[];
  final athletes = <Atleta>[];

  @override
  Future<List<ClubMember>> activeMembers(String clubId) async => [
    for (final m in memberships)
      if (m.clubId == clubId && m.activa) ClubMember(membership: m, name: 'n', email: 'e'),
  ];

  @override
  Future<Usuario?> findUser(String email) async => users[email];

  @override
  Future<Membresia?> findMembership(String clubId, String userId) async =>
      memberships.where((m) => m.clubId == clubId && m.usuarioId == userId).firstOrNull;

  @override
  Future<void> createUser(Usuario user, Club personalClub, Membresia personalMembership, Atleta personalAthlete) async {
    users[user.email] = user;
    memberships.add(personalMembership);
    athletes.add(personalAthlete);
  }

  @override
  Future<void> saveMembership(Membresia membership) async {
    memberships.removeWhere((m) => m.id == membership.id);
    memberships.add(membership);
  }

  @override
  Future<void> ensureAthlete(Atleta athlete) async {
    if (!athletes.any((a) => a.clubId == athlete.clubId && a.usuarioId == athlete.usuarioId)) athletes.add(athlete);
  }
}

void main() {
  const admin = ClubContext(clubId: 'c1', userId: 'a', roles: {Rol.coach, Rol.adminClub}, clubType: TipoClub.club);
  var n = 0;
  late _FakeStore store;
  late RegisterMember register;
  final audit = Auditoria.nueva('a', ahora: DateTime.utc(2026));

  Membresia membership(String user, Set<Rol> roles) => Membresia(
    id: 'm-$user',
    clubId: 'c1',
    usuarioId: user,
    roles: roles,
    estado: EstadoMembresia.activa,
    desde: DateTime.utc(2026),
    auditoria: audit,
  );

  setUp(() {
    store = _FakeStore();
    register = RegisterMember(store, now: () => DateTime.utc(2026, 11, 8), newId: () => 'id${n++}');
  });

  final Matcher rejected = throwsA(isA<ErrorDeSolicitud>());

  test('a new email gets a user, a personal club and the membership', () async {
    final member = await register(admin, {'email': ' Nuevo@X.com', 'nombre': 'Nuevo', 'roles': ['coach']});
    expect(member.email, 'nuevo@x.com');
    expect(member.membership.roles, {Rol.coach});
    expect(store.users, contains('nuevo@x.com'));
    expect(store.memberships.where((m) => m.clubId == 'c1'), hasLength(1));
  });

  test('a new email needs a name; the roles and email must be valid', () async {
    await expectLater(register(admin, {'email': 'a@x.com', 'roles': ['coach']}), rejected);
    await expectLater(register(admin, {'email': 'nope', 'nombre': 'N', 'roles': ['coach']}), rejected);
    await expectLater(register(admin, {'email': 'a@x.com', 'nombre': 'N', 'roles': <String>[]}), rejected);
    await expectLater(register(admin, {'email': 'a@x.com', 'nombre': 'N', 'roles': ['rey']}), rejected);
  });

  test('a coach can be made club admin, keeping one membership', () async {
    final user = Usuario(id: 'u1', email: 'c@x.com', nombre: 'C', emailVerificado: true, clubPersonalId: 'p');
    store.users['c@x.com'] = user;
    store.memberships
      ..add(membership('u1', {Rol.coach}))
      ..add(membership('a', {Rol.coach, Rol.adminClub}));
    await register(admin, {'email': 'c@x.com', 'roles': ['coach', 'admin_club']});
    expect(store.memberships.where((m) => m.usuarioId == 'u1'), hasLength(1));
    expect(store.memberships.firstWhere((m) => m.usuarioId == 'u1').roles, {Rol.coach, Rol.adminClub});
  });

  test('the club keeps at least one admin and one coach', () async {
    final user = Usuario(id: 'a', email: 'a@x.com', nombre: 'A', emailVerificado: true, clubPersonalId: 'p');
    store.users['a@x.com'] = user;
    store.memberships.add(membership('a', {Rol.coach, Rol.adminClub}));
    await expectLater(register(admin, {'email': 'a@x.com', 'roles': ['coach']}), rejected);
    await expectLater(register(admin, {'email': 'a@x.com', 'roles': ['admin_club']}), rejected);
  });

  test('the athlete role creates the athlete profile', () async {
    await register(admin, {'email': 'b@x.com', 'nombre': 'B', 'roles': ['atleta']});
    expect(store.athletes.where((a) => a.clubId == 'c1'), hasLength(1));
  });
}
