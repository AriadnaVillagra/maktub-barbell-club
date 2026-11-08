import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/plan/domain/plan_repository.dart';
import 'package:maktub_frontend/features/plan/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_frontend/features/wods/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../wods/fakes.dart';

Plan samplePlan({
  String id = 'p1',
  String name = 'Fuerza',
  PlanType type = PlanType.regular,
  List<WeekModel> models = const [],
  List<String> assignment = const [],
  PublishedPlan? published,
}) => Plan(
  id: id,
  clubId: 'c1',
  name: name,
  type: type,
  weekModels: models,
  weekAssignment: assignment,
  published: published,
  auditoria: Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1)),
);

/// A published copy of [plan]'s saved content.
PublishedPlan publishedCopyOf(Plan plan) => PublishedPlan(
  weekModels: plan.weekModels,
  weekAssignment: plan.weekAssignment,
  publishedAt: DateTime.utc(2026, 11, 7),
  publishedBy: 'u1',
);

WeekModel model(String id, String name, int days) => WeekModel(
  id: id,
  name: name,
  days: [for (var i = 0; i < days; i++) PlanDay(name: 'D$id${i + 1}')],
);

class FakePlanRepository implements PlanRepository {
  FakePlanRepository({List<Plan> plans = const [], this.failure})
    : stored = {for (final p in plans) p.id: p};

  final Map<String, Plan> stored;
  final Object? failure;
  final calls = <String>[];

  /// Plans sent to [save], in order.
  final saved = <Plan>[];

  /// When set, [save] throws it instead of storing.
  Object? saveFailure;

  /// When set, [save] waits for it before answering.
  Future<void>? saveGate;

  /// Plan ids sent to [publish], in order.
  final published = <String>[];

  /// When set, [publish] throws it instead of publishing.
  Object? publishFailure;

  /// When set, [publish] waits for it before answering.
  Future<void>? publishGate;

  @override
  Future<List<PlanSummary>> plans(String clubId) async {
    calls.add('plans:$clubId');
    if (failure != null) throw failure!;
    return [
      for (final p in stored.values)
        PlanSummary(
          id: p.id,
          name: p.name,
          type: p.type,
          modelCount: p.weekModels.length,
          published: p.published != null,
          hasUnpublishedChanges: p.hasUnpublishedChanges,
        ),
    ];
  }

  @override
  Future<Plan> create(
    String clubId, {
    required String name,
    required PlanType type,
  }) async {
    calls.add('create:$clubId:$name:${type.cable}');
    final plan = samplePlan(id: 'new${stored.length}', name: name, type: type);
    stored[plan.id] = plan;
    return plan;
  }

  @override
  Future<Plan> save(String clubId, Plan plan) async {
    calls.add('save:$clubId:${plan.id}');
    saved.add(plan);
    await saveGate;
    if (saveFailure != null) throw saveFailure!;
    final stored = Plan(
      id: plan.id,
      clubId: clubId,
      name: plan.name,
      type: plan.type,
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      // The server keeps its own published copy, whatever the client sends.
      published: this.stored[plan.id]?.published,
      auditoria: Auditoria(
        creadoPor: 'u1',
        creadoEn: DateTime.utc(2026, 11, 1),
        modificadoPor: 'u1',
        modificadoEn: DateTime.utc(2026, 11, 8),
      ),
    );
    this.stored[plan.id] = stored;
    return stored;
  }

  @override
  Future<Plan> publish(String clubId, String planId) async {
    calls.add('publish:$clubId:$planId');
    published.add(planId);
    await publishGate;
    if (publishFailure != null) throw publishFailure!;
    final current = stored[planId]!;
    final result = Plan(
      id: current.id,
      clubId: current.clubId,
      name: current.name,
      type: current.type,
      weekModels: current.weekModels,
      weekAssignment: current.weekAssignment,
      published: publishedCopyOf(current),
      auditoria: current.auditoria,
    );
    stored[planId] = result;
    return result;
  }

  @override
  Future<Plan> plan(String clubId, String planId) async {
    calls.add('plan:$clubId:$planId');
    if (failure != null) throw failure!;
    return stored[planId] ?? (throw StateError('no plan $planId'));
  }
}

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

/// Overrides shared by the plan widget tests: signed in as [roles] in club `c1`.
List<Override> planOverrides(
  FakePlanRepository repo, {
  Set<Rol> roles = const {Rol.coach},
  FakeCatalogAdminRepository? catalog,
  FakeWodRepository? wods,
}) => [
  catalogRepositoryProvider.overrideWithValue(
    catalog ?? FakeCatalogAdminRepository(),
  ),
  catalogAdminRepositoryProvider.overrideWithValue(
    catalog ?? FakeCatalogAdminRepository(),
  ),
  sessionControllerProvider.overrideWith(_SignedIn.new),
  meRepositoryProvider.overrideWithValue(
    FakeMeRepository(meWith([(club('c1', 'Gimnasio', TipoClub.club), roles)])),
  ),
  planRepositoryProvider.overrideWithValue(repo),
  wodRepositoryProvider.overrideWithValue(wods ?? FakeWodRepository()),
];

Future<void> pumpPlanPage(
  WidgetTester tester,
  Widget page,
  FakePlanRepository repo, {
  FakeCatalogAdminRepository? catalog,
  FakeWodRepository? wods,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: planOverrides(repo, catalog: catalog, wods: wods),
      child: MaterialApp(theme: TemaMaktub.claro(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}
