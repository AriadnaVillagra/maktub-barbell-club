import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/domain/me.dart';
import 'package:maktub_frontend/features/access/domain/me_repository.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';

import 'fakes.dart';

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

/// `GET /me` with whatever roles an admin left the user with.
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

/// Roles changed from another session reach this one when the app comes back to the front (refreshMe), without F5.
void main() {
  Future<_MutableMe> pump(WidgetTester tester, Set<Rol> roles) async {
    final me = _MutableMe(roles);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(me),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Column(
              children: [
                Text('admin: ${ref.watch(canManageMembersProvider)}'),
                TextButton(onPressed: () => refreshMe(ref), child: const Text('refresh')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return me;
  }

  testWidgets('a role given from another session shows up', (tester) async {
    final me = await pump(tester, {Rol.coach, Rol.atleta});
    expect(find.text('admin: false'), findsOneWidget);

    me.roles = {Rol.coach, Rol.atleta, Rol.adminClub};
    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();

    expect(find.text('admin: true'), findsOneWidget);
  });

  testWidgets('when nothing changed, who the user is is not replaced', (tester) async {
    final me = await pump(tester, {Rol.coach});

    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();

    expect(me.fetches, 2, reason: 'the first load and the check; no third fetch from replacing it');
  });
}
