import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../../core/red/cliente_api.dart';
import '../../access/presentation/providers.dart';
import '../../catalogo/presentation/exercise_catalog_providers.dart';
import '../data/http_plan_repository.dart';
import '../domain/plan_draft.dart';
import '../domain/plan_repository.dart';
import 'plan_problem_messages.dart';

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

/// The plan [planId] being edited in memory. It is discarded when the editor closes; [planSaveProvider] saves it.
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

  /// After a save: [saved] is what the server stored for [sent]. When nothing was edited since [sent] the
  /// draft restarts from [saved] (clean); otherwise the edits made while saving are kept on top of it.
  void commitSaved(PlanDraft sent, Plan saved) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      identical(current, sent)
          ? PlanDraft.from(saved)
          : current.rebasedOn(saved),
    );
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
  void addPrescription(
    String modelId,
    int day,
    int block,
    Prescription prescription,
  ) => _edit((d) => d.addPrescription(modelId, day, block, prescription));
  void removePrescription(String modelId, int day, int block, int index) =>
      _edit((d) => d.removePrescription(modelId, day, block, index));
  void updatePrescription(
    String modelId,
    int day,
    int block,
    int index,
    Prescription prescription,
  ) => _edit(
    (d) => d.updatePrescription(modelId, day, block, index, prescription),
  );
}

/// Where saving the plan stands: in flight, refused with a list of problems, failed, or done.
class PlanSaveState {
  const PlanSaveState({
    this.saving = false,
    this.title,
    this.problems = const [],
    this.error,
    this.justSaved = false,
  });

  final bool saving;

  /// Heading of the problem list; null when there is no list.
  final String? title;
  final List<PlanProblemLine> problems;

  /// A failure that is not a list of problems (network, permission, server).
  final String? error;
  final bool justSaved;

  bool get hasFailure => error != null || problems.isNotEmpty;
}

final planSaveProvider = NotifierProvider.autoDispose
    .family<PlanSave, PlanSaveState, String>(PlanSave.new);

/// Validates the draft with `validatePlan` (the server's rule) and sends it unless a problem blocks saving.
/// An unfinished plan is saved and what it still lacks is listed. Any failure leaves the draft as it was; a
/// second save while one is in flight is ignored.
class PlanSave extends Notifier<PlanSaveState> {
  PlanSave(this.planId);

  final String planId;

  @override
  PlanSaveState build() => const PlanSaveState();

  Future<void> save() async {
    if (state.saving) return;
    final editor = ref.read(planEditorProvider(planId).notifier);
    final draft = ref.read(planEditorProvider(planId)).value;
    if (draft == null) return;
    state = const PlanSaveState(saving: true);
    final plan = draft.toPlan();
    String? Function(String) nameOf = (_) => null;
    try {
      final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
      if (clubId == null) throw StateError('No active club');
      final exercises = {
        for (final e in await ref.read(catalogExercisesProvider.future)) e.id: e,
      };
      nameOf = (id) => exercises[id]?.name;
      final problems = validatePlan(plan, exerciseById: (id) => exercises[id]);
      final blocking = problems.where((p) => p.blocksSaving).toList();
      if (blocking.isNotEmpty) {
        _rejected(plan, blocking, nameOf, null);
        return;
      }
      final saved = await ref.read(planRepositoryProvider).save(clubId, plan);
      if (!ref.mounted) return;
      editor.commitSaved(draft, saved);
      ref.invalidate(plansProvider);
      state = PlanSaveState(
        justSaved: true,
        title: problems.isEmpty
            ? null
            : 'Plan guardado. Para poder asignarlo falta completar:',
        problems: [
          for (final p in problems)
            describePlanProblem(p, plan, exerciseName: nameOf),
        ],
      );
    } on PlanRejected catch (e) {
      _rejected(plan, e.problems, nameOf, e.message);
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = PlanSaveState(error: e.mensaje);
    } catch (_) {
      if (ref.mounted) {
        state = const PlanSaveState(error: 'No se pudo guardar el plan.');
      }
    }
  }

  void _rejected(
    Plan plan,
    List<PlanProblem> problems,
    String? Function(String) nameOf,
    String? serverMessage,
  ) {
    if (!ref.mounted) return;
    state = PlanSaveState(
      title:
          serverMessage ??
          (problems.length == 1
              ? 'El plan tiene 1 problema; no se guardó.'
              : 'El plan tiene ${problems.length} problemas; no se guardó.'),
      problems: [
        for (final p in problems)
          describePlanProblem(p, plan, exerciseName: nameOf),
      ],
    );
  }
}
