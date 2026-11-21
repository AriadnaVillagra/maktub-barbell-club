import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/modos.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/features/access/data/chosen_club_me_repository.dart';
import 'package:maktub_frontend/features/access/data/shared_preferences_chosen_club_store.dart';
import 'package:maktub_frontend/features/access/domain/all_clubs_repository.dart';
import 'package:maktub_frontend/features/access/domain/chosen_club_store.dart';
import 'package:maktub_frontend/features/access/presentation/club_picker_page.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

class _MemoryChosenClub implements ChosenClubStore {
  final picks = <String, Club>{};

  @override
  Future<Club?> read(String userId) async => picks[userId];

  @override
  Future<void> write(String userId, Club? club) async =>
      club == null ? picks.remove(userId) : picks[userId] = club;
}

class _AllClubs implements AllClubsRepository {
  _AllClubs(this.clubs);

  final List<Club> clubs;

  @override
  Future<List<Club>> allClubs() async => clubs;
}

void main() {
  final gym = club('c1', 'Maktub', TipoClub.club);
  final foreign = club('c9', 'Barra Norte', TipoClub.club);

  late _MemoryChosenClub store;

  setUp(() => store = _MemoryChosenClub());

  Future<ProviderContainer> mount(WidgetTester tester, {bool platformAdmin = true, String location = Rutas.club}) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: Rutas.preferencias,
          builder: (_, _) => const PaginaPreferencias(),
          routes: [GoRoute(path: 'club', builder: (_, _) => const ClubPickerPage())],
        ),
      ],
    );
    addTearDown(router.dispose);
    final me = meWith([(gym, {Rol.atleta})], isPlatformAdmin: platformAdmin);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          chosenClubStoreProvider.overrideWithValue(store),
          meRepositoryProvider.overrideWithValue(ChosenClubMeRepository(FakeMeRepository(me), store)),
          allClubsRepositoryProvider.overrideWithValue(_AllClubs([foreign, gym])),
        ],
        child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('Preferencias offers the club picker only to platform admins', (tester) async {
    await mount(tester, location: Rutas.preferencias);
    expect(find.byKey(const Key('preferencia-${Rutas.club}')), findsOneWidget);

    await mount(tester, platformAdmin: false, location: Rutas.preferencias);
    expect(find.byKey(const Key('preferencia-${Rutas.club}')), findsNothing);
  });

  testWidgets('lists every club, marks the active one, and picking another makes it active with every action', (
    tester,
  ) async {
    final container = await mount(tester);
    expect(find.text('Barra Norte'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('club-picker-c1'))).selected, isTrue);

    await tester.tap(find.byKey(const Key('club-picker-c9')));
    await tester.pumpAndSettle();

    final me = container.read(meProvider).value!;
    expect(me.activeClub?.club.id, 'c9');
    expect((me.canPlan, me.canEditEquipment, me.canManageMembers), (true, true, true));
    expect(store.picks['u1']?.id, 'c9');
    expect(tester.widget<ListTile>(find.byKey(const Key('club-picker-c9'))).selected, isTrue);
  });

  testWidgets('someone who is not a platform admin sees no list', (tester) async {
    await mount(tester, platformAdmin: false);
    expect(find.text('Barra Norte'), findsNothing);
  });

  group('SharedPreferencesChosenClubStore', () {
    test('keeps the pick per user, and null clears it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesChosenClubStore();
      await prefs.write('u1', foreign);
      expect((await prefs.read('u1'))?.nombre, 'Barra Norte');
      expect(await prefs.read('u2'), isNull);
      await prefs.write('u1', null);
      expect(await prefs.read('u1'), isNull);
    });

    test('unreadable storage reads as no pick', () async {
      SharedPreferences.setMockInitialValues({SharedPreferencesChosenClubStore.key: 'not json'});
      expect(await SharedPreferencesChosenClubStore().read('u1'), isNull);
    });
  });
}
