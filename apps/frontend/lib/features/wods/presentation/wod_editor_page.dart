import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, showNotice;
import '../../catalogo/presentation/exercise_catalog_providers.dart';
import '../../catalogo/presentation/exercise_picker.dart';
import '../../catalogo/presentation/providers.dart';
import '../../../core/red/cliente_api.dart';
import '../../plan/presentation/plan_labels.dart' show setsSummary;
import '../../plan/presentation/prescription_dialog.dart';
import '../domain/wod_draft.dart';
import '../domain/wod_repository.dart';
import 'providers.dart';
import 'wod_problem_messages.dart';

/// Creates a WoD ([wodId] null) or edits one of the library: name, description, timer (any type) and
/// exercises of any category with their sets. Nothing is stored until Guardar; a refused or failed save
/// keeps the form as it is and shows what the server said.
class WodEditorPage extends ConsumerWidget {
  const WodEditorPage({super.key, this.wodId, required this.listPath});

  final String? wodId;

  /// The WoD list, where saving and leaving go.
  final String listPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(wodId == null ? 'Nuevo WoD' : 'Editar WoD')),
    body: wodId == null
        ? _WodForm(listPath: listPath)
        : asyncView(
            ref.watch(wodsProvider),
            onRetry: () => ref.invalidate(wodsProvider),
            builder: (wods) {
              for (final w in wods) {
                if (w.id == wodId) {
                  return _WodForm(
                    key: ValueKey(w.id),
                    wod: w,
                    listPath: listPath,
                  );
                }
              }
              return const Center(
                child: Text('No existe el WoD.', key: Key('wod-missing')),
              );
            },
          ),
  );
}

class _WodForm extends ConsumerStatefulWidget {
  const _WodForm({super.key, this.wod, required this.listPath});

  final Wod? wod;
  final String listPath;

  @override
  ConsumerState<_WodForm> createState() => _WodFormState();
}

class _WodFormState extends ConsumerState<_WodForm> {
  late WodDraft _draft = widget.wod == null
      ? const WodDraft()
      : WodDraft.from(widget.wod!);
  late final _name = TextEditingController(text: _draft.name);
  late final _description = TextEditingController(text: _draft.description);
  bool _saving = false;
  String? _errorTitle;
  List<ProblemaMaktub> _problems = const [];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  List<ProblemaMaktub> _describe(Iterable<WodProblem> problems) => [
    for (final p in problems)
      ProblemaMaktub(
        wodProblemMessage(p.code),
        ubicacion: p.prescriptionIndex == null
            ? null
            : 'Ejercicio ${p.prescriptionIndex! + 1}',
      ),
  ];

  Future<void> _addExercise() async {
    // A WoD accepts every category: no category fixed, chips to narrow the list.
    final exercise = await showExercisePicker(
      context,
      showCategoryFilter: true,
    );
    if (exercise == null) return;
    setState(
      () => _draft = _draft.addPrescription(
        Prescription(exerciseId: exercise.id),
      ),
    );
  }

  Future<void> _editPrescription(int i, Exercise? exercise) async {
    final edited = await askPrescription(
      context,
      initial: _draft.prescriptions[i],
      exercise: exercise,
      inheritedTimerLabel: 'El del WoD',
    );
    if (edited != null) {
      setState(() => _draft = _draft.updatePrescription(i, edited));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final problems = _draft.problems;
    if (problems.isNotEmpty) {
      setState(() {
        _errorTitle = 'No se guardó el WoD.';
        _problems = _describe(problems);
      });
      return;
    }
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    setState(() {
      _saving = true;
      _errorTitle = null;
      _problems = const [];
    });
    final repo = ref.read(wodRepositoryProvider);
    try {
      if (widget.wod == null) {
        await repo.create(clubId, _draft);
      } else {
        await repo.save(clubId, widget.wod!.id, _draft);
      }
      ref.invalidate(wodsProvider);
      if (!mounted) return;
      showNotice(context, 'WoD guardado.');
      context.go(widget.listPath);
    } on WodRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorTitle = e.message;
        _problems = _describe(e.problems);
      });
    } on ErrorDeApi catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorTitle = e.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorTitle = 'No se pudo guardar el WoD.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(catalogExercisesProvider).value ?? const [];
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    Exercise? exerciseOf(String? id) {
      for (final e in exercises) {
        if (e.id == id) return e;
      }
      return null;
    }

    String timerLabel(String id) {
      for (final t in timers) {
        if (t.id == id) return t.nombre;
      }
      return id;
    }

    String detail(Prescription p) => [
      if (p.timerId != null) 'Temporizador: ${timerLabel(p.timerId!)}',
      if (p.note != null) p.note!,
    ].join(' · ');

    // Active timers of any type, plus the current choice even if it was archived since.
    final timerItems = [
      for (final t in timers)
        if (t.estado == CatalogStatus.active || t.id == _draft.timerId) t,
    ];
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        if (_errorTitle != null) ...[
          ListaDeProblemas(
            key: const Key('wod-problems'),
            titulo: _errorTitle!,
            problemas: _problems,
          ),
          const SizedBox(height: Espacio.l),
        ],
        TextField(
          key: const Key('wod-name-field'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (t) => _draft = _draft.withName(t),
        ),
        const SizedBox(height: Espacio.l),
        TextField(
          key: const Key('wod-description-field'),
          controller: _description,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Descripción'),
          onChanged: (t) => _draft = _draft.withDescription(t),
        ),
        const SizedBox(height: Espacio.l),
        DropdownButtonFormField<String?>(
          key: const Key('wod-timer-field'),
          initialValue: timerItems.any((t) => t.id == _draft.timerId)
              ? _draft.timerId
              : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Temporizador'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Ninguno'),
            ),
            for (final t in timerItems)
              DropdownMenuItem<String?>(value: t.id, child: Text(t.nombre)),
          ],
          onChanged: (id) => setState(() => _draft = _draft.withTimer(id)),
        ),
        const SizedBox(height: Espacio.xl),
        Text('Ejercicios', style: context.textos.titleMedium),
        const SizedBox(height: Espacio.s),
        for (final (i, p) in _draft.prescriptions.indexed) ...[
          if (i > 0) const Divider(),
          ListTile(
            key: Key('wod-prescription-$i'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => _editPrescription(i, exerciseOf(p.exerciseId)),
            title: Row(
              spacing: Espacio.l,
              children: [
                Flexible(
                  child: Text(
                    exerciseOf(p.exerciseId)?.name ??
                        p.exerciseId ??
                        'Sin ejercicio',
                  ),
                ),
                if (p.sets.isNotEmpty)
                  Flexible(child: Text(setsSummary(p.sets))),
              ],
            ),
            subtitle: detail(p).isEmpty ? null : Text(detail(p)),
            trailing: IconButton(
              key: Key('wod-prescription-remove-$i'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Quitar ejercicio',
              onPressed: () =>
                  setState(() => _draft = _draft.removePrescription(i)),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('wod-exercise-add'),
            icon: const Icon(Icons.add),
            label: const Text('Agregar ejercicio'),
            onPressed: _addExercise,
          ),
        ),
        const SizedBox(height: Espacio.xl),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('wod-save'),
            icon: _saving
                ? const SizedBox.square(
                    dimension: Espacio.l,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
