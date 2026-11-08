import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../domain/exercise_draft.dart';
import '../domain/exercise_list_rules.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'catalog_labels.dart';
import 'exercise_catalog_providers.dart';
import 'exercise_picker.dart';
import 'providers.dart';

/// Create / edit form of an exercise of the club.
///
/// - [exerciseId]: edits that exercise.
/// - [copyFromId]: creates a new custom one prefilled from that (default) exercise.
/// - neither: a blank new exercise.
class ExerciseFormPage extends ConsumerWidget {
  const ExerciseFormPage({
    super.key,
    required this.basePath,
    this.exerciseId,
    this.copyFromId,
  });

  final String basePath;
  final String? exerciseId;
  final String? copyFromId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = [
      ref.watch(catalogExercisesProvider),
      ref.watch(catalogCategoriesProvider),
      ref.watch(muscleGroupsProvider),
      ref.watch(movementPatternsProvider),
    ];
    final failed = lists.where((l) => l.hasError).firstOrNull;
    final title = exerciseId != null ? 'Editar ejercicio' : 'Nuevo ejercicio';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: failed != null
          ? Center(child: Text(errorMessage(failed.error!)))
          : lists.any((l) => !l.hasValue)
          ? const Center(child: CircularProgressIndicator())
          : _ExerciseForm(
              basePath: basePath,
              exercises: ref.watch(catalogExercisesProvider).requireValue,
              categories: ref.watch(catalogCategoriesProvider).requireValue,
              groups: ref.watch(muscleGroupsProvider).requireValue,
              patterns: ref.watch(movementPatternsProvider).requireValue,
              exerciseId: exerciseId,
              copyFromId: copyFromId,
            ),
    );
  }
}

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({
    required this.basePath,
    required this.exercises,
    required this.categories,
    required this.groups,
    required this.patterns,
    this.exerciseId,
    this.copyFromId,
  });

  final String basePath;
  final List<Exercise> exercises;
  final List<Category> categories;
  final List<MuscleGroup> groups;
  final List<MovementPattern> patterns;
  final String? exerciseId;
  final String? copyFromId;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late Set<String> _categoryIds;
  late Set<Metric> _metrics;
  Metric? _defaultMetric;
  String? _patternId;
  late Map<String, MuscleWeight> _muscles;
  late LoadReferenceKind _referenceKind;
  String? _referenceExerciseId;
  late List<String> _suggestionIds;
  double? _barKg;
  late bool _isBase;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.exercises
        .where((e) => e.id == (widget.exerciseId ?? widget.copyFromId))
        .firstOrNull;
    final copying = widget.exerciseId == null && source != null;
    final draft = source == null
        ? const ExerciseDraft(name: '')
        : ExerciseDraft.from(
            source,
            name: copying ? '${source.name} (custom)' : null,
          );
    _name = TextEditingController(text: draft.name);
    _notes = TextEditingController(text: draft.notes ?? '');
    _categoryIds = {...draft.categoryIds};
    _metrics = {...draft.metrics};
    _defaultMetric = draft.defaultMetric;
    _patternId = draft.patternId;
    _muscles = {for (final m in draft.muscles) m.groupId: m.weight};
    _referenceKind = draft.loadReference.kind;
    _referenceExerciseId = draft.loadReference.exerciseId;
    _suggestionIds = draft.suggestionIds;
    _barKg = draft.barKg;
    // Only editing a default keeps it default: a default can only use other default items.
    _isBase = widget.exerciseId != null && source?.scope == CatalogScope.base;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  ExerciseDraft _draft() => ExerciseDraft(
    name: _name.text.trim(),
    categoryIds: _categoryIds.toList(),
    metrics: _metrics.toList(),
    defaultMetric: _defaultMetric,
    patternId: _patternId,
    muscles: [
      for (final e in _muscles.entries)
        MuscleShare(groupId: e.key, weight: e.value),
    ],
    loadReference: _referenceKind == LoadReferenceKind.otherExercise
        ? LoadReference.otherExercise(_referenceExerciseId ?? '')
        : LoadReference(_referenceKind),
    suggestionIds: _suggestionIds,
    notes: _notes.text,
    barKg: _usesBar ? _barKg : null,
  );

  bool get _usesBar => _metrics.any((m) => m.isLoad);

  List<Exercise> get _referenceTargets => referenceCandidates(
    widget.exercises,
    clubId: ref.read(catalogClubIdProvider) ?? '',
    exerciseId: widget.exerciseId,
    defaultMetric: _defaultMetric,
    metrics: _metrics,
    baseOnly: _isBase,
  );

  /// Forgets the chosen reference when the new metrics no longer allow it.
  void _dropInvalidReference() {
    if (!_referenceTargets.any((e) => e.id == _referenceExerciseId)) {
      _referenceExerciseId = null;
    }
  }

  Future<void> _pickReference() async {
    final chosen = await showExerciseSearchSheet(context, _referenceTargets);
    if (chosen != null && mounted) setState(() => _referenceExerciseId = chosen.id);
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'El nombre es obligatorio.';
    if (_referenceKind == LoadReferenceKind.otherExercise &&
        _referenceExerciseId == null) {
      return 'Elegí el ejercicio de referencia.';
    }
    final reps =
        _metrics.contains(Metric.reps) && _metrics.any((m) => m.isLoad);
    if (_referenceKind == LoadReferenceKind.own && !reps) {
      return 'El RM propio necesita medir carga y repeticiones.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(catalogRepositoryProvider);
    try {
      final saved = widget.exerciseId == null
          ? await repo.createExercise(clubId, _draft())
          : await repo.updateExercise(clubId, widget.exerciseId!, _draft());
      refreshExercises(ref);
      if (mounted) context.go('${widget.basePath}/ejercicios/${saved.id}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textos;
    bool allowed(DelClub item) => !_isBase || scopeOf(item) == CatalogScope.base;
    final categories = widget.categories.where(
      (c) =>
          allowed(c) &&
          (c.status == CatalogStatus.active || _categoryIds.contains(c.id)),
    );
    final patterns = widget.patterns.where(allowed);
    final groups = widget.groups.where(allowed);
    final team = ref.watch(clubTeamProvider).value;
    final barWeights = {
      for (final b in team?.barras ?? const <ItemInventario>[]) b.kg,
      if ((_barKg ?? noBarKg) != noBarKg) _barKg!,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final shownBar = barChoice(
      _barKg,
      metrics: _metrics,
      clubBarKg: team?.barraKg ?? noBarKg,
    );
    final referenceName = widget.exercises
        .where((e) => e.id == _referenceExerciseId)
        .firstOrNull
        ?.name;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Espacio.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Espacio.l,
        children: [
          TextField(
            key: const ValueKey('field-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          Text('Categorías', style: t.titleMedium),
          Wrap(
            spacing: Espacio.s,
            children: [
              for (final c in categories)
                FilterChip(
                  label: Text(c.name),
                  selected: _categoryIds.contains(c.id),
                  onSelected: (on) => setState(
                    () =>
                        on ? _categoryIds.add(c.id) : _categoryIds.remove(c.id),
                  ),
                ),
            ],
          ),
          Text('Métricas', style: t.titleMedium),
          Wrap(
            spacing: Espacio.s,
            children: [
              for (final m in Metric.values)
                FilterChip(
                  label: Text(metricLabel(m)),
                  selected: _metrics.contains(m),
                  onSelected: (on) => setState(() {
                    on ? _metrics.add(m) : _metrics.remove(m);
                    if (!_metrics.contains(_defaultMetric)) {
                      _defaultMetric = null;
                    }
                    _dropInvalidReference();
                  }),
                ),
            ],
          ),
          DropdownButtonFormField<Metric?>(
            key: ValueKey('default-metric-${_metrics.length}'),
            initialValue: _defaultMetric,
            decoration: const InputDecoration(labelText: 'Métrica objetivo'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Ninguna')),
              for (final m in Metric.values.where(_metrics.contains))
                DropdownMenuItem(value: m, child: Text(metricLabel(m))),
            ],
            onChanged: (v) => setState(() {
              _defaultMetric = v;
              _dropInvalidReference();
            }),
          ),
          DropdownButtonFormField<String?>(
            key: const ValueKey('field-pattern'),
            initialValue: _patternId,
            decoration: const InputDecoration(
              labelText: 'Patrón de movimiento',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin patrón')),
              for (final p in patterns)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _patternId = v),
          ),
          Text('Músculos', style: t.titleMedium),
          for (final g in groups)
            Row(
              key: ValueKey('muscle-${g.id}'),
              spacing: Espacio.s,
              children: [
                Expanded(child: Text(g.name)),
                SegmentedButton<MuscleWeight>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    for (final w in MuscleWeight.values)
                      ButtonSegment(
                        value: w,
                        label: Text(muscleWeightLabel(w)),
                      ),
                  ],
                  selected: {?_muscles[g.id]},
                  onSelectionChanged: (s) => setState(() {
                    s.isEmpty
                        ? _muscles.remove(g.id)
                        : _muscles[g.id] = s.single;
                  }),
                ),
              ],
            ),
          DropdownButtonFormField<LoadReferenceKind>(
            key: const ValueKey('field-reference'),
            initialValue: _referenceKind,
            decoration: const InputDecoration(labelText: 'Referencia de carga'),
            items: [
              for (final k in LoadReferenceKind.values)
                DropdownMenuItem(value: k, child: Text(referenceKindLabel(k))),
            ],
            onChanged: (v) => setState(() {
              _referenceKind = v ?? LoadReferenceKind.none;
              if (_referenceKind != LoadReferenceKind.otherExercise) {
                _referenceExerciseId = null;
              }
            }),
          ),
          if (_referenceKind == LoadReferenceKind.otherExercise)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Ejercicio de referencia',
                suffixIcon: Icon(Icons.search),
              ),
              child: InkWell(
                key: const ValueKey('field-reference-exercise'),
                onTap: _pickReference,
                child: Text(referenceName ?? 'Elegir ejercicio'),
              ),
            ),
          if (_usesBar)
            DropdownButtonFormField<double>(
              key: ValueKey('field-bar-${barWeights.length}-$shownBar'),
              initialValue: shownBar,
              decoration: const InputDecoration(labelText: 'Barra'),
              items: [
                for (final kg in barWeights)
                  DropdownMenuItem(value: kg, child: Text('${formatKg(kg)} kg')),
                const DropdownMenuItem(value: noBarKg, child: Text('Sin barra')),
              ],
              onChanged: (v) => setState(() => _barKg = v),
            ),
          TextField(
            key: const ValueKey('field-notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            maxLength: maxExerciseNotes,
            decoration: const InputDecoration(labelText: 'Notas'),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('form-error'),
              style: t.bodyMedium!.copyWith(color: context.esquema.error),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              widget.exerciseId == null ? 'Crear ejercicio' : 'Guardar cambios',
            ),
          ),
        ],
      ),
    );
  }
}
