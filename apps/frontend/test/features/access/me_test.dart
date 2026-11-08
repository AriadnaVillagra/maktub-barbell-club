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
}
