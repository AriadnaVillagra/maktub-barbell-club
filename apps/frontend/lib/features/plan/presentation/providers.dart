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

/// Creates a new plan named [name] with the week models and cycle assignment of [source], saved as a draft
/// and active, so it can be completed and published on its own. A history plan's copy is a regular plan.
/// Returns null without an active club. Errors propagate.
Future<Plan?> copyPlanAsNew(WidgetRef ref, Plan source, String name) async {
  final created = await createPlan(
    ref,
    name: name,
    type: source.type == PlanType.history ? PlanType.regular : source.type,
  );
  if (created == null) return null;
  final saved = await ref
      .read(planRepositoryProvider)
      .save(
        created.clubId,
        Plan(
          id: created.id,
          clubId: created.clubId,
          name: created.name,
          type: created.type,
          weekModels: source.weekModels,
          weekAssignment: source.weekAssignment,
          auditoria: created.auditoria,
        ),
      );
  ref.invalidate(plansProvider);
  return saved;
}

/// What the editor scrolls to after it is built: the key name (`model-<id>`, `day-<model>-<i>`,
/// `block-<model>-<day>-<i>`, `prescription-<model>-<day>-<block>-<i>`) of the last thing added. The widget
/// with that name scrolls itself into view and clears it ([RevealOnAdd]). One editor is open at a time.
final planRevealProvider = NotifierProvider.autoDispose<PlanReveal, String?>(
  PlanReveal.new,
);

class PlanReveal extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String target) => state = target;

  /// Called by the revealed widget, only if it is still the target.
  void done(String target) {
    if (state == target) state = null;
  }
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

  /// Applies an addition and, when it changed the draft, asks the editor to scroll to what was added
  /// ([target] reads the new draft).
  void _add(
    PlanDraft Function(PlanDraft) change,
    String? Function(PlanDraft) target,
  ) {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    if (identical(next, current)) return;
    state = AsyncData(next);
    final t = target(next);
    if (t != null) ref.read(planRevealProvider.notifier).show(t);
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

  void addModel(String name) =>
      _add((d) => d.addModel(name), (d) => 'model-${d.weekModels.last.id}');
  void setPast(bool value) => _edit((d) => d.setPast(value));
  void renameModel(String id, String name) =>
      _edit((d) => d.renameModel(id, name));
  void removeModel(String id) => _edit((d) => d.removeModel(id));
  void assign(int week, String? modelId) =>
      _edit((d) => d.assign(week, modelId));
  void addDay(String modelId) =>
      _add((d) => d.addDay(modelId), (d) => _lastDay(d, modelId));
  void copyDayTo(String fromModelId, int index, String toModelId) => _add(
    (d) => d.copyDayTo(fromModelId, index, toModelId),
    (d) => _lastDay(d, toModelId),
  );

  static String? _lastDay(PlanDraft d, String modelId) {
    final days = d.modelById(modelId)?.days.length ?? 0;
    return days == 0 ? null : 'day-$modelId-${days - 1}';
  }

  static int _blockCount(PlanDraft d, String modelId, int day) {
    final days = d.modelById(modelId)?.days ?? const [];
    return day < days.length ? days[day].blocks.length : 0;
  }

  static int _prescriptionCount(
    PlanDraft d,
    String modelId,
    int day,
    int block,
  ) {
    final days = d.modelById(modelId)?.days ?? const [];
    if (day >= days.length || block >= days[day].blocks.length) return 0;
    return days[day].blocks[block].prescriptions.length;
  }

  void removeDay(String modelId, int index) =>
      _edit((d) => d.removeDay(modelId, index));
  void moveDay(String modelId, int from, int to) =>
      _edit((d) => d.moveDay(modelId, from, to));
  void addBlock(String modelId, int day, PlanBlock block) => _add(
    (d) => d.addBlock(modelId, day, block),
    (d) => 'block-$modelId-$day-${_blockCount(d, modelId, day) - 1}',
  );
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
  ) => _add(
    (d) => d.addPrescription(modelId, day, block, prescription),
    (d) =>
        'prescription-$modelId-$day-$block-${_prescriptionCount(d, modelId, day, block) - 1}',
  );

  /// A WoD adds several exercises at once: the editor goes to its block.
  void addWod(String modelId, int day, int block, Wod wod) => _add(
    (d) => d.addWod(modelId, day, block, wod),
    (_) => 'block-$modelId-$day-$block',
  );
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
        for (final e in await ref.read(catalogExercisesProvider.future))
          e.id: e,
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
            : plan.type == PlanType.history
            // A history plan is never assigned; validatePlan does not ask it for % or reps.
            ? 'Plan guardado. Para poder publicarlo falta completar:'
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

/// Whether "Publicar" is offered: the plan is saved (no unsaved edits), `validatePlan` finds nothing to fix
/// and there is something to publish (never published, or the saved content differs from the published copy,
/// compared through its JSON form). False while the draft or the exercises are loading.
final planPublishableProvider = Provider.autoDispose.family<bool, String>((
  ref,
  planId,
) {
  final draft = ref.watch(planEditorProvider(planId)).value;
  final exercises = ref.watch(catalogExercisesProvider).value;
  if (draft == null || exercises == null) return false;
  if (draft.isDirty || !draft.base.hasUnpublishedChanges) return false;
  final byId = {for (final e in exercises) e.id: e};
  return validatePlan(draft.toPlan(), exerciseById: (id) => byId[id]).isEmpty;
});

/// Where publishing the plan stands: in flight, refused with a list of problems, failed, or done.
class PlanPublishState {
  const PlanPublishState({
    this.publishing = false,
    this.title,
    this.problems = const [],
    this.error,
    this.justPublished = false,
  });

  final bool publishing;

  /// Heading of the problem list; null when there is no list.
  final String? title;
  final List<PlanProblemLine> problems;

  /// A failure that is not a list of problems (network, permission, conflict, server).
  final String? error;
  final bool justPublished;
}

final planPublishProvider = NotifierProvider.autoDispose
    .family<PlanPublish, PlanPublishState, String>(PlanPublish.new);

/// Asks the server to publish the saved plan. The server is the judge: a 422 lists the problems it found. The
/// draft in the editor survives: the plan the server returns becomes its base, so the published copy updates
/// and any edits made meanwhile stay. A second publish while one is in flight is ignored.
class PlanPublish extends Notifier<PlanPublishState> {
  PlanPublish(this.planId);

  final String planId;

  @override
  PlanPublishState build() => const PlanPublishState();

  Future<void> publish() async {
    if (state.publishing) return;
    final draft = ref.read(planEditorProvider(planId)).value;
    if (draft == null || draft.isDirty) return;
    final editor = ref.read(planEditorProvider(planId).notifier);
    final plan = draft.toPlan();
    state = const PlanPublishState(publishing: true);
    String? Function(String) nameOf = (_) => null;
    try {
      final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
      if (clubId == null) throw StateError('No active club');
      final exercises = {
        for (final e in await ref.read(catalogExercisesProvider.future))
          e.id: e,
      };
      nameOf = (id) => exercises[id]?.name;
      final published = await ref
          .read(planRepositoryProvider)
          .publish(clubId, planId);
      if (!ref.mounted) return;
      editor.commitSaved(draft, published);
      ref.invalidate(plansProvider);
      state = const PlanPublishState(justPublished: true);
    } on PlanRejected catch (e) {
      if (!ref.mounted) return;
      state = PlanPublishState(
        title: e.message,
        problems: [
          for (final p in e.problems)
            describePlanProblem(p, plan, exerciseName: nameOf),
        ],
      );
    } on ErrorDeApi catch (e) {
      if (ref.mounted) state = PlanPublishState(error: e.mensaje);
    } catch (_) {
      if (ref.mounted) {
        state = const PlanPublishState(error: 'No se pudo publicar el plan.');
      }
    }
  }
}
