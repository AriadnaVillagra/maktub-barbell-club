import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../data/http_plan_repository.dart';
import '../domain/plan_draft.dart';
import '../domain/plan_repository.dart';

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => HttpPlanRepository(ref.watch(clienteApiProvider)),
);

/// The plans of the active club, by name.
final plansProvider = FutureProvider<List<PlanSummary>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(planRepositoryProvider).plans(clubId);
});

/// Creates an empty plan in the active club and refreshes the list. Returns null without an active club.
Future<Plan?> createPlan(
  WidgetRef ref, {
  required String name,
  required PlanType type,
}) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return null;
  final plan = await ref
      .read(planRepositoryProvider)
      .create(clubId, name: name, type: type);
  ref.invalidate(plansProvider);
  return plan;
}

/// The plan [planId] being edited in memory. It is discarded when the editor closes: saving is E5.9.
final planEditorProvider = AsyncNotifierProvider.autoDispose
    .family<PlanEditor, PlanDraft, String>(PlanEditor.new);

class PlanEditor extends AsyncNotifier<PlanDraft> {
  PlanEditor(this.planId);

  final String planId;

  @override
  Future<PlanDraft> build() async {
    final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
    if (clubId == null) throw StateError('No active club');
    return PlanDraft.from(
      await ref.watch(planRepositoryProvider).plan(clubId, planId),
    );
  }

  void _edit(PlanDraft Function(PlanDraft) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }

  void addModel(String name) => _edit((d) => d.addModel(name));
  void renameModel(String id, String name) =>
      _edit((d) => d.renameModel(id, name));
  void removeModel(String id) => _edit((d) => d.removeModel(id));
  void assign(int week, String? modelId) =>
      _edit((d) => d.assign(week, modelId));
  void addDay(String modelId) => _edit((d) => d.addDay(modelId));
  void removeDay(String modelId, int index) =>
      _edit((d) => d.removeDay(modelId, index));
  void moveDay(String modelId, int from, int to) =>
      _edit((d) => d.moveDay(modelId, from, to));
  void addBlock(String modelId, int day, PlanBlock block) =>
      _edit((d) => d.addBlock(modelId, day, block));
  void removeBlock(String modelId, int day, int index) =>
      _edit((d) => d.removeBlock(modelId, day, index));
  void moveBlock(String modelId, int day, int from, int to) =>
      _edit((d) => d.moveBlock(modelId, day, from, to));
  void updateBlock(
    String modelId,
    int day,
    int index,
    PlanBlock Function(PlanBlock) change,
  ) => _edit((d) => d.updateBlock(modelId, day, index, change));
}
