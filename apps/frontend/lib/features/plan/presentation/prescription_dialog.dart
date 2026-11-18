import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../domain/athlete_loads.dart';
import '../domain/prescription_edit.dart';
import 'plan_labels.dart';

/// Edits a prescription: its sets one by one (reps always; `%` if the exercise is loaded by % of RM; kg
/// if it has a fixed load), the note, its own timer and the bar override. Returns the edited prescription,
/// or null if cancelled. Nothing is validated here (E5.9 does it when saving). [inheritedTimerLabel] names
/// what an empty timer means: the block's timer in a plan, the WoD's in the library. "Sin temporizador"
/// ([noTimerId]) turns it off for this exercise only.
///
/// A set of an exercise loaded by % of RM is typed in % or in kg (E5.16): typing one clears the other, and each of
/// [athletes] with an RM gets the other value worked out and frozen in the set, shown under it.
Future<Prescription?> askPrescription(
  BuildContext context, {
  required Prescription initial,
  required Exercise? exercise,
  String inheritedTimerLabel = 'El del bloque',
  PrescriptionAthletes athletes = const PrescriptionAthletes(),
}) => showDialog<Prescription>(
  context: context,
  builder: (_) => _PrescriptionDialog(
    initial: initial,
    exercise: exercise,
    inheritedTimerLabel: inheritedTimerLabel,
    athletes: athletes,
  ),
);

/// Who a prescription's % and kg are worked out for (E5.16), with their RM and factor for its exercise, and the
/// equipment that rounds the kilos (the standard one when null). The plan's assignment, or the athletes chosen in
/// the editor's Detalles card when it has none.
class PrescriptionAthletes {
  const PrescriptionAthletes({this.athletes = const [], this.equipo});

  final List<AthleteBasis> athletes;
  final Equipo? equipo;
}

final _decimalText = RegExp(r'^\d*[.,]?\d*$');

/// Keeps only digits.
final _wholeFormatter = FilteringTextInputFormatter.digitsOnly;

/// Keeps digits and one decimal separator (comma or point).
final _decimalFormatter = TextInputFormatter.withFunction(
  (old, value) => _decimalText.hasMatch(value.text) ? value : old,
);

class _PrescriptionDialog extends ConsumerStatefulWidget {
  const _PrescriptionDialog({
    required this.initial,
    required this.exercise,
    required this.inheritedTimerLabel,
    required this.athletes,
  });

  final Prescription initial;
  final Exercise? exercise;
  final String inheritedTimerLabel;
  final PrescriptionAthletes athletes;

  @override
  ConsumerState<_PrescriptionDialog> createState() =>
      _PrescriptionDialogState();
}

class _PrescriptionDialogState extends ConsumerState<_PrescriptionDialog> {
  late List<PlanSet> _sets = widget.initial.sets.isEmpty
      ? const [PlanSet()]
      : widget.initial.sets;
  late String _note = widget.initial.note ?? '';
  late String? _timerId = widget.initial.timerId;
  late String _bar = widget.initial.barKg == null
      ? ''
      : formatNumber(widget.initial.barKg!);

  /// Changes whenever rows are added or removed, so the fields are rebuilt with the new initial texts.
  int _generation = 0;

  /// Per set, how many times typing the other field cleared its % or its kg field (rebuilt empty, not focused).
  final _pctCleared = <int, int>{};
  final _kgCleared = <int, int>{};

  String _clearedSuffix(Map<int, int> cleared, int i) => (cleared[i] ?? 0) == 0 ? '' : '-${cleared[i]}';

  /// The bar the kilos are rounded on: the one typed here, else the exercise's.
  double? get _barKg => parseTypedNumber(_bar) ?? widget.exercise?.barKg;

  List<AthleteBasis> get _athletes => widget.athletes.athletes;

  Map<String, AthleteSetLoad> _loadsFor(double? pct, double? kg) => athleteLoads(
    pct: pct,
    kg: kg,
    athletes: _athletes,
    equipo: widget.athletes.equipo ?? Equipo.estandarDe(''),
    barKg: _barKg,
  );


  /// The one athlete the loads are for, when there is exactly one and they have an RM: their % and kg then go in the
  /// set's own fields instead of a line under it.
  AthleteBasis? get _single {
    final athletes = _athletes;
    return athletes.length == 1 && (athletes.single.rm ?? 0) > 0 ? athletes.single : null;
  }

  /// [s] worked out again from its % ([fromPct]) or from its kg (E5.16): each athlete's loads, and with a single
  /// athlete the other field too. With several, only what was typed is kept.
  PlanSet _workedOut(PlanSet s, {required bool fromPct}) {
    final pct = fromPct ? s.pct : null;
    final kg = fromPct ? null : s.kg;
    final loads = _loadsFor(pct, kg);
    final own = _single == null ? null : loads[_single!.id];
    return setWith(
      s,
      reps: s.reps,
      pct: fromPct ? pct : own?.pct,
      kg: fromPct ? own?.kg : kg,
      byAthlete: loads,
    );
  }

  /// Rebuilds the fields of set [i] whose value [after] changed from [before], without touching the one being typed.
  void _refreshFields(int i, PlanSet before, PlanSet after, {bool? typedPct}) {
    if (typedPct != true && before.pct != after.pct) _pctCleared[i] = (_pctCleared[i] ?? 0) + 1;
    if (typedPct != false && before.kg != after.kg) _kgCleared[i] = (_kgCleared[i] ?? 0) + 1;
  }

  /// Typed in % or in kg on a % exercise (E5.16).
  void _typeLoad(int i, {required bool inPct, required double? value}) {
    final before = _sets[i];
    final typed = setWith(
      before,
      reps: before.reps,
      pct: inPct ? value : before.pct,
      kg: inPct ? before.kg : value,
    );
    final after = _workedOut(typed, fromPct: inPct);
    setState(() {
      _refreshFields(i, before, after, typedPct: inPct);
      _sets = [for (final (j, x) in _sets.indexed) j == i ? after : x];
    });
  }

  /// A new bar rounds the kilos differently: the sets typed in % for several athletes are worked out again. With a
  /// single athlete both fields are filled and it is not known which was typed, so they stay.
  void _rebar() {
    _sets = [
      for (final s in _sets)
        s.byAthlete.isEmpty || s.pct == null || s.kg != null ? s : _workedOut(s, fromPct: true),
    ];
  }


  bool get _hasPct =>
      widget.exercise?.metrics.contains(Metric.loadPctRm) ??
      _sets.any((s) => s.pct != null);
  bool get _hasKg =>
      widget.exercise?.metrics.contains(Metric.fixedLoad) ??
      _sets.any((s) => s.kg != null);

  void _changeSet(
    int i, {
    int? Function(PlanSet)? reps,
    double? Function(PlanSet)? pct,
    double? Function(PlanSet)? kg,
  }) {
    final s = _sets[i];
    _sets = [
      for (final (j, x) in _sets.indexed)
        j == i
            ? setWith(
                s,
                reps: reps == null ? s.reps : reps(s),
                pct: pct == null ? s.pct : pct(s),
                kg: kg == null ? s.kg : kg(s),
              )
            : x,
    ];
  }

  void _submit() => Navigator.pop(
    context,
    prescriptionWith(
      widget.initial,
      sets: _sets,
      note: _note,
      timerId: _timerId,
      barKg: parseTypedNumber(_bar),
    ),
  );

  Widget _numberField({
    required Key key,
    required String label,
    required String initial,
    required List<TextInputFormatter> formatters,
    required ValueChanged<String> onChanged,
  }) => Expanded(
    child: TextFormField(
      key: key,
      initialValue: initial,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    final timerItems = [
      for (final t in timers)
        if (t.estado == CatalogStatus.active || t.id == _timerId) t,
    ];
    final exerciseBar = widget.exercise?.barKg;
    return AlertDialog(
      title: Text(widget.exercise?.name ?? 'Ejercicio'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, set) in _sets.indexed) ...[
                Row(
                  key: Key('set-row-$i'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: Espacio.xl,
                      child: Text('${i + 1}', style: context.textos.labelLarge),
                    ),
                    _numberField(
                      key: ValueKey('set-reps-$i-$_generation'),
                      label: 'Reps',
                      initial: set.reps?.toString() ?? '',
                      formatters: [_wholeFormatter],
                      onChanged: (t) =>
                          _changeSet(i, reps: (_) => parseTypedReps(t)),
                    ),
                    if (_hasPct) ...[
                      const SizedBox(width: Espacio.s),
                      _numberField(
                        key: ValueKey('set-pct-$i-$_generation${_clearedSuffix(_pctCleared, i)}'),
                        label: '%',
                        initial: set.pct == null ? '' : formatNumber(set.pct!),
                        formatters: [_decimalFormatter],
                        onChanged: (t) => _typeLoad(i, inPct: true, value: parseTypedNumber(t)),
                      ),
                      const SizedBox(width: Espacio.s),
                      _numberField(
                        key: ValueKey('set-kg-$i-$_generation${_clearedSuffix(_kgCleared, i)}'),
                        label: 'kg',
                        initial: set.kg == null ? '' : formatNumber(set.kg!),
                        formatters: [_decimalFormatter],
                        onChanged: (t) => _typeLoad(i, inPct: false, value: parseTypedNumber(t)),
                      ),
                    ] else if (_hasKg) ...[
                      const SizedBox(width: Espacio.s),
                      _numberField(
                        key: ValueKey('set-kg-$i-$_generation'),
                        label: 'kg',
                        initial: set.kg == null ? '' : formatNumber(set.kg!),
                        formatters: [_decimalFormatter],
                        onChanged: (t) =>
                            _changeSet(i, kg: (_) => parseTypedNumber(t)),
                      ),
                    ],
                    IconButton(
                      key: Key('set-remove-$i'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar serie',
                      onPressed: _sets.length <= 1
                          ? null
                          : () => setState(() {
                              _sets = removeSet(_sets, i);
                              _generation++;
                              _pctCleared.clear();
                              _kgCleared.clear();
                            }),
                    ),
                  ],
                ),
                if (_single == null
                    ? athleteLoadsSummary(set.byAthlete, _athletes, formatNumber)
                    : '' case final line
                    when line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: Espacio.xl, bottom: Espacio.s),
                    child: Text(
                      line,
                      key: Key('set-athletes-$i'),
                      style: context.textos.bodySmall?.copyWith(color: context.esquema.onSurfaceVariant),
                    ),
                  ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('set-add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar serie'),
                  onPressed: () => setState(() {
                    _sets = addSet(_sets);
                    _generation++;
                  }),
                ),
              ),
              const SizedBox(height: Espacio.s),
              TextFormField(
                key: const Key('prescription-note-field'),
                initialValue: _note,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Nota'),
                onChanged: (t) => _note = t,
              ),
              const SizedBox(height: Espacio.l),
              DropdownButtonFormField<String?>(
                key: const Key('prescription-timer-field'),
                initialValue:
                    _timerId == noTimerId ||
                        timerItems.any((t) => t.id == _timerId)
                    ? _timerId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Temporizador'),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(widget.inheritedTimerLabel),
                  ),
                  const DropdownMenuItem<String?>(
                    value: noTimerId,
                    child: Text('Sin temporizador'),
                  ),
                  for (final t in timerItems)
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(t.nombre),
                    ),
                ],
                onChanged: (id) => setState(() => _timerId = id),
              ),
              const SizedBox(height: Espacio.l),
              TextFormField(
                key: const Key('prescription-bar-field'),
                initialValue: _bar,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_decimalFormatter],
                decoration: InputDecoration(
                  labelText: 'Barra (kg)',
                  helperText: switch (exerciseBar) {
                    null => 'Vacío: la del ejercicio',
                    noBarKg => 'Vacío: el ejercicio va sin barra',
                    final kg =>
                      'Vacío: la del ejercicio (${formatNumber(kg)} kg)',
                  },
                ),
                onChanged: (t) => setState(() {
                  _bar = t;
                  _rebar();
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('prescription-ok'),
          onPressed: _submit,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
