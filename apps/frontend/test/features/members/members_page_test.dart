import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/domain/me.dart';
import 'package:maktub_frontend/features/access/domain/me_repository.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/members/domain/members_repository.dart';
import 'package:maktub_frontend/features/members/presentation/members_page.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

/// `GET /me` answers with whatever roles the user has at the moment.
class _MutableMe implements MeRepository {
  _MutableMe(this.roles);

  Set<Rol> roles;
  int fetches = 0;

  @override
  Future<Me> fetch() async {
    fetches++;
    return meWith([(club('c1', 'Maktub', TipoClub.club), roles)]);
  }
}

/// The club's members; changing the signed-in user's roles also changes what `GET /me` answers.
class _FakeMembers implements MembersRepository {
  _FakeMembers(this.me);

  final _MutableMe me;
  var listCalls = 0;

  @override
  Future<List<ClubMember>> members(String clubId) async {
    listCalls++;
    return [ClubMember(userId: 'u1', name: 'Ari', email: 'ari@example.com', roles: me.roles)];
  }

  @override
  Future<ClubMember> register(
    String clubId, {
    required String email,
    required String name,
    required Set<Rol> roles,
  }) async {
    me.roles = roles;
    return ClubMember(userId: 'u1', name: 'Ari', email: email, roles: roles);
  }
}

void main() {
  testWidgets('taking away your own club admin role leaves Miembros with a notice instead of an error', (
    tester,
  ) async {
    final me = _MutableMe({Rol.coach, Rol.atleta, Rol.adminClub});
    final members = _FakeMembers(me);
    final router = GoRouter(
      initialLocation: '/preferencias/miembros',
      routes: [
        GoRoute(
          path: '/preferencias',
          builder: (_, _) => const Scaffold(body: Text('Preferencias')),
          routes: [GoRoute(path: 'miembros', builder: (_, _) => const MembersPage(exitPath: '/preferencias'))],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(me),
          membersRepositoryProvider.overrideWithValue(members),
        ],
        child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('member-u1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-role-admin_club')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-save')));
    await tester.pumpAndSettle();

    expect(find.text('Preferencias'), findsOneWidget);
    expect(find.textContaining('Ya no administrás el club'), findsOneWidget);
    expect(find.text('Tu rol en este club no permite esta acción.'), findsNothing);
    expect(members.listCalls, 1, reason: 'the list is not asked for again');
    expect(me.fetches, 2, reason: 'the roles are fetched again');
  });
}
