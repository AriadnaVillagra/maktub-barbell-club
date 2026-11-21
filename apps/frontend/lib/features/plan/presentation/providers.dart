import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../../core/red/cliente_api.dart';
import '../../access/presentation/providers.dart';
import '../../catalogo/domain/exercise_draft.dart';
import '../../catalogo/presentation/exercise_catalog_providers.dart';
import '../../catalogo/presentation/providers.dart'
    show activeExercisesProvider, catalogRepositoryProvider;
import '../data/http_plan_repository.dart';
import '../data/shared_preferences_models_view_store.dart';
import '../domain/models_view.dart';
import '../domain/load_promotion.dart';
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

/// Deletes [plan] with its assignments and refreshes the list (E8.9). Errors propagate.
Future<void> deletePlan(WidgetRef ref, Plan plan) async {
  await ref.read(planRepositoryProvider).delete(plan.clubId, plan.id);
  ref.invalidate(plansProvider);
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

final modelsViewStoreProvider = Provider<ModelsViewStore>(
  (ref) => SharedPreferencesModelsViewStore(),
);

/// How the editor shows the week models, remembered on the device. Starts detailed until the saved one
/// loads; a choice made before that wins.
class ModelsViewController extends Notifier<ModelsView> {
  var _chosen = false;

  @override
  ModelsView build() {
    unawaited(_restore());
    return ModelsView.detailed;
  }

  Future<void> _restore() async {
    final saved = await ref.read(modelsViewStoreProvider).load();
    if (saved != null && !_chosen && ref.mounted) state = saved;
  }

  void choose(ModelsView view) {
    _chosen = true;
    state = view;
    unawaited(ref.read(modelsViewStoreProvider).save(view));
  }
}

final modelsViewProvider = NotifierProvider<ModelsViewController, ModelsView>(
  ModelsViewController.new,
);

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
  void copyModel(String id) =>
      _add((d) => d.copyModel(id), (d) => 'model-${d.weekModels.last.id}');
  void setPast(bool value) => _edit((d) => d.setPast(value));
  void setVisibility(PlanVisibility value) => _edit((d) => d.setVisibility(value));
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
    this.gainedLoad = const [],
    this.loadFailed = const [],
  });

  final bool saving;

  /// Heading of the problem list; null when there is no list.
  final String? title;
  final List<PlanProblemLine> problems;

  /// A failure that is not a list of problems (network, permission, server).
  final String? error;
  final bool justSaved;

  /// Names of the exercises this save made weighted in the catalog, because the plan gives them a weight.
  final List<String> gainedLoad;

  /// Names of those that could not be made weighted: the plan was saved, and the next save tries again.
  final List<String> loadFailed;

  bool get hasFailure => error != null || problems.isNotEmpty;
}

final planSaveProvider = NotifierProvider.autoDispose
    .family<PlanSave, PlanSaveState, String>(PlanSave.new);

/// Validates the draft with `validatePlan` (the server's rule) and sends it unless a problem blocks saving.
/// An unfinished plan is saved and what it still lacks is listed. Any failure leaves the draft as it was; a
/// second save while one is in flight is ignored.
///
/// Once the plan is saved, each exercise that is not weighted but got a weight in it, and that the user can change in
/// the catalog, is saved weighted ([exercisesGainingLoad]); the plan is validated as if it already were. Done here and
/// not when the weight is typed, so a weight that is cancelled, erased or never saved changes nothing. A failure there
/// does not undo the plan: the exercise stays as it was and the next save tries again.
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
      final me = await ref.read(meProvider.future);
      final catalog = {
        for (final e in await ref.read(catalogExercisesProvider.future))
          e.id: e,
      };
      final gaining = exercisesGainingLoad(
        plan,
        catalog,
        canWrite: (e) => me?.canWriteExercise(e) ?? false,
      );
      final exercises = {...catalog, ...gaining};
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
      final load = await _saveWeighted(clubId, gaining.values);
      if (!ref.mounted) return;
      state = PlanSaveState(
        justSaved: true,
        gainedLoad: load.saved,
        loadFailed: load.failed,
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

  /// Saves [exercises] (made weighted) in the catalog, one by one, and reloads the catalog when any was saved.
  Future<({List<String> saved, List<String> failed})> _saveWeighted(
    String clubId,
    Iterable<Exercise> exercises,
  ) async {
    final saved = <String>[];
    final failed = <String>[];
    final repo = ref.read(catalogRepositoryProvider);
    for (final e in exercises) {
      try {
        await repo.updateExercise(clubId, e.id, ExerciseDraft.from(e));
        saved.add(e.name);
      } catch (_) {
        failed.add(e.name);
      }
    }
    if (saved.isNotEmpty && ref.mounted) {
      ref.invalidate(catalogExercisesProvider);
      ref.invalidate(activeExercisesProvider);
    }
    return (saved: saved, failed: failed);
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

/// Why "Publicar" is off: [message] says it, and [problems] lists what the plan still lacks, when that is the
/// reason.
class PlanPublishBlock {
  const PlanPublishBlock(this.message, {this.problems = const []});

  final String message;
  final List<PlanProblemLine> problems;
}

/// Why "Publicar" is off for [planId], so the editor can say it; null when it can be published or while the draft or
/// the exercises are loading. What the plan lacks comes first, since it is what to fix; then unsaved edits; then
/// nothing new to publish.
final planPublishBlockProvider = Provider.autoDispose
    .family<PlanPublishBlock?, String>((ref, planId) {
      final draft = ref.watch(planEditorProvider(planId)).value;
      final exercises = ref.watch(catalogExercisesProvider).value;
      if (draft == null || exercises == null) return null;
      final byId = {for (final e in exercises) e.id: e};
      final plan = draft.toPlan();
      final problems = validatePlan(plan, exerciseById: (id) => byId[id]);
      if (problems.isNotEmpty) {
        return PlanPublishBlock(
          problems.length == 1
              ? 'No se puede publicar: falta completar una cosa.'
              : 'No se puede publicar: faltan completar ${problems.length} cosas.',
          problems: [
            for (final p in problems)
              describePlanProblem(
                p,
                plan,
                exerciseName: (id) => byId[id]?.name,
              ),
          ],
        );
      }
      if (draft.isDirty) {
        return const PlanPublishBlock('Guardá los cambios para poder publicar.');
      }
      if (!draft.base.hasUnpublishedChanges) {
        return const PlanPublishBlock(
          'No hay cambios para publicar: los atletas ya ven esta versión.',
        );
      }
      return null;
    });

/// Whether "Publicar" is offered: the plan is saved (no unsaved edits), `validatePlan` finds nothing to fix
/// and there is something to publish (never published, or the saved content differs from the published copy,
/// compared through its JSON form). False while the draft or the exercises are loading.
final planPublishableProvider = Provider.autoDispose.family<bool, String>((
  ref,
  planId,
) {
  final loaded =
      ref.watch(planEditorProvider(planId)).hasValue &&
      ref.watch(catalogExercisesProvider).hasValue;
  return loaded && ref.watch(planPublishBlockProvider(planId)) == null;
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
