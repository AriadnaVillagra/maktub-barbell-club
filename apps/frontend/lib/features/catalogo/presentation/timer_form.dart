import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Opens the timer form as a full screen. Resolves to the edited (or new) timer, or null when dismissed.
/// A new one is a draft: the server sets its id, scope and audit trail. [asBlock]: a block of a Mix.
Future<Temporizador?> showTimerForm(
  BuildContext context, {
  Temporizador? initial,
  bool asBlock = false,
}) => Navigator.of(context).push<Temporizador>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => TimerForm(initial: initial, asBlock: asBlock),
  ),
);

String timerTypeLabel(TipoTemporizador t) => switch (t) {
  TipoTemporizador.amrap => 'AMRAP',
  TipoTemporizador.forTime => 'For Time',
  TipoTemporizador.emom => 'EMOM',
  TipoTemporizador.tabata => 'Tabata',
  TipoTemporizador.mix => 'Mix',
  TipoTemporizador.countdown => 'Descanso',
  TipoTemporizador.trabajo => 'Trabajo',
};

String _problemLabel(TimerProblem p) => switch (p) {
  TimerProblem.nameEmpty => 'Falta el nombre.',
  TimerProblem.workNotPositive => 'El tiempo debe ser mayor que 0.',
  TimerProblem.restNegative => 'El descanso no puede ser negativo.',
  TimerProblem.roundsNotPositive => 'Las rondas deben ser al menos 1.',
  TimerProblem.setsNotPositive => 'Las series deben ser al menos 1.',
  TimerProblem.setRestNegative => 'El descanso entre series no puede ser negativo.',
  TimerProblem.capNotPositive => 'El límite de tiempo debe ser mayor que 0.',
  TimerProblem.signalNotPositive => 'La señal por intervalo debe ser mayor que 0.',
  TimerProblem.blocksEmpty => 'Agregá al menos un bloque.',
  TimerProblem.nestedMix => 'Un Mix no puede tener otro Mix adentro.',
};

/// Seconds from "mm:ss" or plain seconds; null if it doesn't parse.
int? parseClock(String text) {
  final t = text.trim();
  if (!t.contains(':')) return int.tryParse(t);
  final parts = t.split(':');
  if (parts.length != 2) return null;
  final minutes = int.tryParse(parts[0]);
  final seconds = int.tryParse(parts[1]);
  return minutes == null || seconds == null ? null : minutes * 60 + seconds;
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

class TimerForm extends StatefulWidget {
  const TimerForm({super.key, this.initial, this.asBlock = false});

  final Temporizador? initial;
  final bool asBlock;

  @override
  State<TimerForm> createState() => _TimerFormState();
}

class _TimerFormState extends State<TimerForm> {
  late final _name = TextEditingController(text: widget.initial?.nombre ?? '');
  final _work = TextEditingController();
  final _rest = TextEditingController();
  final _rounds = TextEditingController();
  final _totalMinutes = TextEditingController();
  late final _sets = TextEditingController(text: '${_startSets()}');
  late final _setRest = TextEditingController(text: reloj(widget.initial?.descansoSeriesSeg ?? 60));
  late final _cap = TextEditingController(text: reloj(widget.initial?.limiteSeg ?? 600));
  late final _signal = TextEditingController(text: reloj(widget.initial?.senalCadaSeg ?? 60));
  late TipoTemporizador _type = widget.initial?.tipo ?? TipoTemporizador.amrap;
  late bool _hasSets = (widget.initial?.series ?? 1) > 1;
  late bool _hasCap = widget.initial?.limiteSeg != null;
  late bool _hasSignal = widget.initial?.senalCadaSeg != null;
  late bool _deathBy = widget.initial?.deathBy ?? false;
  late List<Temporizador> _blocks = [...?widget.initial?.bloques];

  int _startSets() {
    final series = widget.initial?.series ?? 1;
    return series > 1 ? series : 2;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t == null) {
      _applyDefaults(_type);
    } else {
      _work.text = reloj(t.trabajoSeg);
      _rest.text = reloj(t.descansoSeg);
      _rounds.text = '${t.rondas}';
      _totalMinutes.text = _plain(t.rondas * t.trabajoSeg / 60);
    }
  }

  /// Each mode starts from its usual values, so changing the mode never leaves the previous one's numbers.
  void _applyDefaults(TipoTemporizador type) {
    _work.text = switch (type) {
      TipoTemporizador.amrap => '10:00',
      TipoTemporizador.tabata => '00:20',
      _ => '01:00',
    };
    _rest.text = '00:10';
    _rounds.text = type == TipoTemporizador.tabata ? '8' : '1';
    _totalMinutes.text = '10';
  }

  @override
  void dispose() {
    for (final c in [_name, _work, _rest, _rounds, _totalMinutes, _sets, _setRest, _cap, _signal]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEmom => _type == TipoTemporizador.emom;
  bool get _isTabata => _type == TipoTemporizador.tabata;
  bool get _isForTime => _type == TipoTemporizador.forTime;
  bool get _isMix => _type == TipoTemporizador.mix;
  bool get _usesSets => _isEmom || _isTabata || _isForTime || _type == TipoTemporizador.amrap;

  int get _rawRounds {
    if (_isEmom) {
      final every = parseClock(_work.text) ?? 0;
      final minutes = double.tryParse(_totalMinutes.text.trim().replaceAll(',', '.')) ?? 0;
      return _deathBy ? 1 : (every > 0 ? minutes * 60 ~/ every : 0);
    }
    return _isTabata || _isMix ? (int.tryParse(_rounds.text.trim()) ?? 0) : 1;
  }

  Temporizador get _draft {
    final base = widget.initial;
    final sets = _usesSets && _hasSets;
    return Temporizador(
      id: base?.id ?? '',
      clubId: base?.clubId ?? clubPlataforma,
      nombre: _name.text.trim(),
      tipo: _type,
      trabajoSeg: _isForTime || _isMix ? 0 : (parseClock(_work.text) ?? 0),
      descansoSeg: _isTabata ? (parseClock(_rest.text) ?? -1) : 0,
      rondas: _rawRounds,
      series: sets ? (int.tryParse(_sets.text.trim()) ?? 0) : 1,
      descansoSeriesSeg: sets ? (parseClock(_setRest.text) ?? -1) : 0,
      limiteSeg: _isForTime && _hasCap ? (parseClock(_cap.text) ?? 0) : null,
      senalCadaSeg: _isForTime && _hasSignal ? (parseClock(_signal.text) ?? 0) : null,
      deathBy: _isEmom && _deathBy,
      bloques: _isMix ? _blocks : const [],
      estado: base?.estado ?? CatalogStatus.active,
      auditoria: base?.auditoria,
    );
  }

  List<TipoTemporizador> get _types => widget.asBlock
      ? const [
          TipoTemporizador.amrap,
          TipoTemporizador.forTime,
          TipoTemporizador.emom,
          TipoTemporizador.tabata,
          TipoTemporizador.trabajo,
          TipoTemporizador.countdown,
        ]
      : const [
          TipoTemporizador.amrap,
          TipoTemporizador.forTime,
          TipoTemporizador.emom,
          TipoTemporizador.tabata,
          TipoTemporizador.mix,
          TipoTemporizador.countdown,
        ];

  Future<void> _editBlock({Temporizador? block, int? index}) async {
    final edited = await showTimerForm(context, initial: block, asBlock: true);
    if (edited == null || !mounted) return;
    setState(() {
      if (index == null) {
        _blocks = [..._blocks, edited];
      } else {
        _blocks = [..._blocks]..[index] = edited;
      }
    });
  }

  String _totalLabel(Temporizador draft) {
    final total = duracionTotalSeg(draft);
    return total == null ? 'Sin tiempo fijo' : 'Tiempo total: ${reloj(total)}';
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problems = draft.validar(comoBloque: widget.asBlock);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nuevo temporizador' : 'Editar temporizador'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: FilledButton(
            key: const Key('timer-save'),
            onPressed: problems.isEmpty ? () => Navigator.pop(context, _draft) : null,
            child: const Text('Guardar'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Espacio.l),
        children: [
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.xs,
            children: [
              for (final t in _types)
                ChoiceChip(
                  key: Key('timer-type-${t.cable}'),
                  label: Text(timerTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    if (t != _type) _applyDefaults(t);
                    _type = t;
                  }),
                ),
            ],
          ),
          const SizedBox(height: Espacio.l),
          _field('timer-name', _name, widget.asBlock ? 'Etiqueta (opcional)' : 'Nombre', numeric: false),
          ..._modeFields(),
          if (_usesSets) ..._setFields(),
          const SizedBox(height: Espacio.l),
          if (problems.isNotEmpty)
            for (final p in problems)
              Text(_problemLabel(p), style: context.textos.bodyMedium?.copyWith(color: context.esquema.error))
          else
            Text(_totalLabel(draft), key: const Key('timer-preview'), style: context.textos.titleMedium),
        ],
      ),
    );
  }

  List<Widget> _modeFields() {
    if (_isEmom) {
      return [
        _clock('timer-work', _work, 'Cada'),
        SwitchListTile(
          key: const Key('timer-death-by'),
          contentPadding: EdgeInsets.zero,
          title: const Text('El mayor tiempo posible (Death By)'),
          value: _deathBy,
          onChanged: (v) => setState(() => _deathBy = v),
        ),
        if (!_deathBy) _field('timer-total', _totalMinutes, 'Por (minutos)'),
      ];
    }
    if (_isTabata) {
      return [
        _field('timer-rounds', _rounds, 'Rondas'),
        _clock('timer-work', _work, 'Trabajo'),
        _clock('timer-rest', _rest, 'Descanso'),
      ];
    }
    if (_isForTime) {
      return [
        _toggle('timer-cap-on', 'Límite de tiempo', _hasCap, (v) => _hasCap = v),
        if (_hasCap) _clock('timer-cap', _cap, 'Límite'),
        _toggle('timer-signal-on', 'Señal por intervalo', _hasSignal, (v) => _hasSignal = v),
        if (_hasSignal) _clock('timer-signal', _signal, 'Señal cada'),
      ];
    }
    if (_isMix) return _mixFields();
    return [_clock('timer-work', _work, 'Duración')];
  }

  List<Widget> _setFields() => [
    _toggle(
      'timer-sets-on',
      _type == TipoTemporizador.amrap ? 'Varios AMRAP' : 'Añadir series',
      _hasSets,
      (v) => _hasSets = v,
    ),
    if (_hasSets) ...[
      _field('timer-sets', _sets, 'Series'),
      _clock('timer-set-rest', _setRest, 'Descanso entre series'),
    ],
  ];

  List<Widget> _mixFields() => [
    _field('timer-rounds', _rounds, 'Repetir la secuencia (veces)'),
    const SizedBox(height: Espacio.m),
    Text('Bloques', style: context.textos.titleSmall),
    ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) => setState(() {
        final list = [..._blocks];
        list.insert(to, list.removeAt(from));
        _blocks = list;
      }),
      children: [
        for (final (i, b) in _blocks.indexed)
          ListTile(
            key: ValueKey('timer-block-$i'),
            contentPadding: EdgeInsets.zero,
            title: Text(b.nombre.isEmpty ? timerTypeLabel(b.tipo) : b.nombre),
            subtitle: Text(describirTemporizador(b)),
            onTap: () => _editBlock(block: b, index: i),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('timer-block-copy-$i'),
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Duplicar',
                  onPressed: () => setState(() => _blocks = [..._blocks]..insert(i + 1, b)),
                ),
                IconButton(
                  key: Key('timer-block-remove-$i'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Quitar',
                  onPressed: () => setState(() => _blocks = [..._blocks]..removeAt(i)),
                ),
                ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
              ],
            ),
          ),
      ],
    ),
    OutlinedButton.icon(
      key: const Key('timer-block-add'),
      onPressed: _editBlock,
      icon: const Icon(Icons.add),
      label: const Text('Agregar bloque'),
    ),
  ];

  Widget _toggle(String key, String label, bool value, ValueChanged<bool> apply) => SwitchListTile(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: (v) => setState(() => apply(v)),
  );

  Widget _clock(String key, TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(top: Espacio.m),
    child: TextField(
      key: Key(key),
      controller: c,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(labelText: label, helperText: 'mm:ss'),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _field(String key, TextEditingController c, String label, {bool numeric = true}) => Padding(
    padding: const EdgeInsets.only(top: Espacio.m),
    child: TextField(
      key: Key(key),
      controller: c,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    ),
  );
}
