import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Opens the timer form in a dialog. Resolves to the edited (or new) timer, or null when dismissed.
/// A new one is a draft: the server sets its id, scope and audit trail.
Future<Temporizador?> showTimerForm(
  BuildContext context, {
  Temporizador? initial,
}) => showDialog<Temporizador>(
  context: context,
  builder: (_) => TimerForm(initial: initial),
);

String _typeLabel(TipoTemporizador t) => switch (t) {
  TipoTemporizador.countdown => 'Cuenta regresiva',
  TipoTemporizador.emom => 'EMOM',
  TipoTemporizador.tabata => 'Tabata',
};

String _problemLabel(TimerProblem p) => switch (p) {
  TimerProblem.nameEmpty => 'Falta el nombre.',
  TimerProblem.workNotPositive => 'El tiempo de trabajo debe ser mayor que 0.',
  TimerProblem.restNegative => 'El descanso no puede ser negativo.',
  TimerProblem.roundsNotPositive => 'Las rondas deben ser al menos 1.',
};

class TimerForm extends StatefulWidget {
  const TimerForm({super.key, this.initial});

  final Temporizador? initial;

  @override
  State<TimerForm> createState() => _TimerFormState();
}

class _TimerFormState extends State<TimerForm> {
  late final _name = TextEditingController(text: widget.initial?.nombre ?? '');
  late final _work = TextEditingController(
    text: '${widget.initial?.trabajoSeg ?? 60}',
  );
  late final _rest = TextEditingController(
    text: '${widget.initial?.descansoSeg ?? 0}',
  );
  late final _rounds = TextEditingController(
    text: '${widget.initial?.rondas ?? 1}',
  );
  late TipoTemporizador _type =
      widget.initial?.tipo ?? TipoTemporizador.countdown;

  @override
  void dispose() {
    _name.dispose();
    _work.dispose();
    _rest.dispose();
    _rounds.dispose();
    super.dispose();
  }

  bool get _usesRest => _type == TipoTemporizador.tabata;
  bool get _usesRounds => _type != TipoTemporizador.countdown;

  Temporizador get _draft {
    final base = widget.initial;
    return Temporizador(
      id: base?.id ?? '',
      clubId: base?.clubId ?? clubPlataforma,
      nombre: _name.text.trim(),
      tipo: _type,
      trabajoSeg: int.tryParse(_work.text.trim()) ?? 0,
      descansoSeg: _usesRest ? (int.tryParse(_rest.text.trim()) ?? -1) : 0,
      rondas: _usesRounds ? (int.tryParse(_rounds.text.trim()) ?? 0) : 1,
      estado: base?.estado ?? CatalogStatus.active,
      auditoria: base?.auditoria,
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problems = draft.validar();
    final phases = problems.isEmpty ? fasesDe(draft) : const <Fase>[];
    final total = phases.fold<int>(0, (sum, f) => sum + f.segundos);
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nuevo temporizador' : 'Editar temporizador',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('timer-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Espacio.m),
            DropdownButtonFormField<TipoTemporizador>(
              key: const Key('timer-type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final t in TipoTemporizador.values)
                  DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
            const SizedBox(height: Espacio.m),
            _number(
              'timer-work',
              _work,
              _type == TipoTemporizador.emom
                  ? 'Segundos por ronda'
                  : 'Segundos de trabajo',
            ),
            if (_usesRest) ...[
              const SizedBox(height: Espacio.m),
              _number('timer-rest', _rest, 'Segundos de descanso'),
            ],
            if (_usesRounds) ...[
              const SizedBox(height: Espacio.m),
              _number('timer-rounds', _rounds, 'Rondas'),
            ],
            const SizedBox(height: Espacio.m),
            if (problems.isNotEmpty)
              for (final p in problems)
                Text(
                  _problemLabel(p),
                  style: context.textos.bodyMedium?.copyWith(
                    color: context.esquema.error,
                  ),
                )
            else
              Text(
                '${phases.length} ${phases.length == 1 ? 'fase' : 'fases'} · ${reloj(total)} en total',
                key: const Key('timer-preview'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('timer-save'),
          onPressed: problems.isEmpty
              ? () => Navigator.pop(context, _draft)
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _number(String key, TextEditingController c, String label) =>
      TextField(
        key: Key(key),
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      );
}
