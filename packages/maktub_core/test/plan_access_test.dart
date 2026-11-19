import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

Plan _plan(PlanVisibility visibility) => Plan(
  id: 'p1',
  clubId: 'c1',
  name: 'Fuerza',
  visibility: visibility,
  auditoria: Auditoria(creadoPor: 'ari', creadoEn: DateTime.utc(2026, 11, 19)),
);

void main() {
  const coach = {Rol.coach, Rol.atleta};
  const admin = {Rol.coach, Rol.atleta, Rol.adminClub};

  (bool, bool, bool) access(PlanVisibility v, String userId, Set<Rol> roles) {
    final a = PlanAccess.of(_plan(v), userId: userId, roles: roles);
    return (a.see, a.edit, a.manage);
  }

  test('its creator reaches it whole, whatever the visibility', () {
    for (final v in PlanVisibility.values) {
      expect(access(v, 'ari', coach), (true, true, true), reason: v.name);
    }
  });

  test('a club admin reaches it whole, whatever the visibility', () {
    for (final v in PlanVisibility.values) {
      expect(access(v, 'andi', admin), (true, true, true), reason: v.name);
    }
  });

  test('another coach: nothing if private, read if shared read-only, edit but not manage if shared editable', () {
    expect(access(PlanVisibility.private, 'kamila', coach), (false, false, false));
    expect(access(PlanVisibility.sharedReadOnly, 'kamila', coach), (true, false, false));
    expect(access(PlanVisibility.sharedEditable, 'kamila', coach), (true, true, false));
  });

  test('travels as "visibilidad"; a plan without it is private', () {
    final shared = _plan(PlanVisibility.sharedEditable);
    expect(shared.toJson()['visibilidad'], 'compartido_edicion');
    expect(Plan.fromJson(shared.toJson()).visibility, PlanVisibility.sharedEditable);
    expect(Plan.fromJson(shared.toJson()..remove('visibilidad')).visibility, PlanVisibility.private);
  });
}
