import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/modos.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/club_requests/domain/club_request_repositories.dart';
import 'package:maktub_frontend/features/club_requests/presentation/club_requests_page.dart';
import 'package:maktub_frontend/features/club_requests/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

ClubRequest _request(String id, String club, {String? note}) => ClubRequest(
  id: id,
  email: '$id@example.com',
  requesterName: 'Persona $id',
  clubName: club,
  note: note,
  auditoria: Auditoria.nueva('$id@example.com', ahora: DateTime.utc(2026, 11, 21, 12)),
);

class _FakeRequests implements ClubRequestsRepository {
  _FakeRequests(this.items);

  final List<ClubRequest> items;
  final approved = <String>[];
  final rejected = <String>[];
  Object? error;

  @override
  Future<List<ClubRequest>> pending() async => [...items];

  @override
  Future<Club> approve(String requestId) async {
    if (error != null) throw error!;
    approved.add(requestId);
    final r = items.firstWhere((r) => r.id == requestId);
    items.remove(r);
    return Club(id: 'c-$requestId', nombre: r.clubName, tipo: TipoClub.club, auditoria: r.auditoria);
  }

  @override
  Future<void> reject(String requestId) async {
    if (error != null) throw error!;
    rejected.add(requestId);
    items.removeWhere((r) => r.id == requestId);
  }
}

void main() {
  late _FakeRequests repo;

  setUp(() {
    repo = _FakeRequests([_request('r1', 'Barra Norte', note: 'Somos 8'), _request('r2', 'Barra Sur')]);
  });

  Future<void> mount(WidgetTester tester, {bool platformAdmin = true, String location = Rutas.pedidosClub}) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: Rutas.preferencias,
          builder: (_, _) => const PaginaPreferencias(),
          routes: [GoRoute(path: 'pedidos-club', builder: (_, _) => const ClubRequestsPage())],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(
            FakeMeRepository(
              meWith([(club('c1', 'Maktub', TipoClub.club), {Rol.coach, Rol.adminClub})], isPlatformAdmin: platformAdmin),
            ),
          ),
          clubRequestsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Preferencias offers the requests only to platform admins', (tester) async {
    await mount(tester, location: Rutas.preferencias);
    expect(find.text('Pedidos de clubes'), findsOneWidget);

    await mount(tester, platformAdmin: false, location: Rutas.preferencias);
    expect(find.text('Pedidos de clubes'), findsNothing);
    expect(find.text('Miembros'), findsOneWidget);
  });

  testWidgets('lists the pending requests', (tester) async {
    await mount(tester);

    expect(find.text('Barra Norte'), findsOneWidget);
    expect(find.text('Persona r1 · r1@example.com'), findsOneWidget);
    expect(find.text('Somos 8'), findsOneWidget);
    expect(find.text('Barra Sur'), findsOneWidget);
  });

  testWidgets('approving asks first, creates the club and takes it off the list', (tester) async {
    await mount(tester);

    await tester.tap(find.byKey(const Key('club-request-approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.approved, isEmpty);

    await tester.tap(find.byKey(const Key('club-request-approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aprobar').last);
    await tester.pumpAndSettle();

    expect(repo.approved, ['r1']);
    expect(find.text('Club "Barra Norte" creado.'), findsOneWidget);
    expect(find.byKey(const Key('club-request-r1')), findsNothing);
    expect(find.byKey(const Key('club-request-r2')), findsOneWidget);
  });

  testWidgets('rejecting takes it off the list; the last one leaves an empty list', (tester) async {
    repo.items.removeLast();
    await mount(tester);

    await tester.tap(find.byKey(const Key('club-request-reject-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar'));
    await tester.pumpAndSettle();

    expect(repo.rejected, ['r1']);
    expect(find.text('No hay pedidos pendientes.'), findsOneWidget);
  });

  testWidgets('an API error is shown and the request stays', (tester) async {
    repo.error = const ErrorDeApi('Ese pedido ya fue rechazado.', estado: 409);
    await mount(tester);

    await tester.tap(find.byKey(const Key('club-request-approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aprobar').last);
    await tester.pumpAndSettle();

    expect(find.text('Ese pedido ya fue rechazado.'), findsOneWidget);
    expect(find.byKey(const Key('club-request-r1')), findsOneWidget);
  });

  testWidgets('someone who is not a platform admin does not see the requests', (tester) async {
    await mount(tester, platformAdmin: false);

    expect(find.text('Solo un administrador de plataforma ve los pedidos de clubes.'), findsOneWidget);
    expect(find.text('Barra Norte'), findsNothing);
  });
}
