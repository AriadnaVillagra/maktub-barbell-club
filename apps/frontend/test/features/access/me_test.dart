import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/domain/me.dart';

import 'fakes.dart';

void main() {
  final gym = club('c1', 'Gimnasio', TipoClub.club);
  final other = club('c2', 'Otro', TipoClub.club);
  final personal = club('personal-1', 'Mi entrenamiento', TipoClub.personal);

  test('an athlete cannot plan, a coach can', () {
    expect(meWith([(gym, {Rol.atleta})]).canPlan, isFalse);
    expect(meWith([(gym, {Rol.coach})]).canPlan, isTrue);
    expect(meWith([(gym, {Rol.coach, Rol.atleta})]).canPlan, isTrue);
  });

  test('the personal club never plans, even with the coach role', () {
    final me = meWith([(personal, {Rol.coach})]);
    expect(me.activeClub?.club.esPersonal, isTrue);
    expect(me.canPlan, isFalse);
  });

  test('the active club is the first non-personal one, whatever the order', () {
    final me = meWith([(personal, {Rol.coach}), (gym, {Rol.atleta}), (other, {Rol.coach})]);
    expect(me.activeClub?.club.id, 'c1');
    expect(me.canPlan, isFalse);
  });

  test('without memberships the active club is the personal one, and there is no planning', () {
    final me = meWith([]);
    expect(me.activeClub?.club.id, 'personal-1');
    expect(me.canPlan, isFalse);
  });

  test('parses the GET /me contract', () {
    final me = Me.fromJson({
      'usuario': meWith([]).user.toJson(),
      'clubPersonal': personal.toJson(),
      'clubes': [
        {'club': gym.toJson(), 'roles': ['coach']},
      ],
      'esAdminPlataforma': false,
    });
    expect(me.canPlan, isTrue);
    expect(me.activeClub?.roles, {Rol.coach});
  });

  test('parses atletaId when present, null or absent (older responses)', () {
    final me = Me.fromJson({
      'usuario': meWith([]).user.toJson(),
      'clubPersonal': null,
      'clubes': [
        {'club': gym.toJson(), 'roles': ['atleta'], 'atletaId': 'ath-1'},
        {'club': other.toJson(), 'roles': ['coach'], 'atletaId': null},
        {'club': personal.toJson(), 'roles': ['coach']},
      ],
    });
    expect([for (final c in me.clubs) c.athleteId], ['ath-1', null, null]);
  });

  group('permissions by hierarchy', () {
    test('a club admin without the coach role plans, edits the catalog, the equipment and the members', () {
      final me = meWith([(gym, {Rol.adminClub})]);
      expect(
        (me.canPlan, me.canEditClubCatalog, me.canEditEquipment, me.canManageMembers, me.canEditReferences),
        (true, true, true, true, true),
      );
    });

    test('a coach edits the catalog (exercises, categories, timers) but not the equipment nor the members', () {
      final me = meWith([(gym, {Rol.coach})]);
      expect((me.canPlan, me.canEditClubCatalog, me.canEditEquipment, me.canManageMembers), (true, true, false, false));
      expect(me.canConfigure, isTrue);
    });

    test('an athlete only trains: no planning, no catalog, no Preferences', () {
      final me = meWith([(gym, {Rol.atleta})]);
      expect((me.canPlan, me.canEditClubCatalog, me.canEditEquipment, me.canConfigure), (false, false, false, false));
    });

    test('a platform admin can do everything in their club, whatever the roles', () {
      final me = meWith([(gym, {Rol.atleta})], isPlatformAdmin: true);
      expect((me.canPlan, me.canEditEquipment, me.canManageMembers, me.canPickAnyClub), (true, true, true, true));
      expect(me.activeClub?.can(Accion.verReportesDeTodos), isTrue);
    });
  });

  group('the chosen club', () {
    test('one of the user\'s clubs becomes the active one', () {
      final me = meWith([(gym, {Rol.coach}), (other, {Rol.atleta})]).withChosenClub(other);
      expect(me.activeClub?.club.id, 'c2');
      expect(me.canPlan, isFalse);
    });

    test('a platform admin works in a club where they are not a member, with every action', () {
      final foreign = club('c9', 'Barra Norte', TipoClub.club);
      final me = meWith([(gym, {Rol.atleta})], isPlatformAdmin: true).withChosenClub(foreign);
      expect(me.activeClub?.club.id, 'c9');
      expect(me.activeClub?.roles, isEmpty);
      expect((me.canPlan, me.canEditEquipment, me.canManageMembers), (true, true, true));
      expect(me.athleteId, isNull);
    });

    test('anyone else ignores a club they cannot reach and stays in the default', () {
      final foreign = club('c9', 'Barra Norte', TipoClub.club);
      expect(meWith([(gym, {Rol.coach})]).withChosenClub(foreign).activeClub?.club.id, 'c1');
    });

    test('is not part of the GET /me copy', () {
      final me = meWith([(gym, {Rol.coach})]);
      expect(me.withChosenClub(other).toJson(), me.toJson());
    });
  });
}
