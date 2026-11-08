import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'providers.dart';

/// The club's inventory: bars and plate pairs with how many there are, and a live preview of the weights
/// they give with each bar. Club admins edit; anyone else only sees it (F2 §6, "Equipo").
class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Equipo')),
    body: asyncView(
      ref.watch(clubTeamProvider),
      onRetry: () => ref.invalidate(clubTeamProvider),
      builder: (team) => team == null
          ? const SizedBox.shrink()
          : _TeamEditor(team: team, canEdit: ref.watch(canEditClubCatalogProvider)),
    ),
  );
}

String _problemLabel(EquipoProblem p) => switch (p) {
  EquipoProblem.noBars => 'Agregá al menos una barra.',
  EquipoProblem.barNotPositive => 'Las barras deben pesar más de 0.',
  EquipoProblem.plateNotPositive => 'Todos los discos deben pesar más de 0.',
  EquipoProblem.duplicateBar => 'Hay dos filas de barra con el mismo peso.',
  EquipoProblem.duplicatePlate => 'Hay dos filas de disco con el mismo peso.',
  EquipoProblem.quantityOutOfRange => 'Las cantidades van de 1 a $maxCantidadInventario.',
  EquipoProblem.tooManyPlates => 'El inventario admite hasta $maxTiposDisco pesos de disco distintos.',
};

double? _parseKg(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// [items] with one more unit of [kg]: a weight already listed gets +1 instead of a second row. Heaviest first.
List<ItemInventario> _withOneMore(List<ItemInventario> items, double kg) {
  final exists = items.any((i) => i.kg == kg);
  return [
    for (final i in items) i.kg == kg ? i.conCantidad((i.cantidad + 1).clamp(1, maxCantidadInventario)) : i,
    if (!exists) ItemInventario(kg),
  ]..sort((a, b) => b.kg.compareTo(a.kg));
}

class _TeamEditor extends ConsumerStatefulWidget {
  const _TeamEditor({required this.team, required this.canEdit});

  final Equipo team;
  final bool canEdit;

  @override
  ConsumerState<_TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends ConsumerState<_TeamEditor> {
  final _bar = TextEditingController();
  final _plate = TextEditingController();
  late List<ItemInventario> _bars = [...widget.team.barras];
  late List<ItemInventario> _plates = [...widget.team.discos];
  double? _previewBar;
  bool _saving = false;

  @override
  void dispose() {
    _bar.dispose();
    _plate.dispose();
    super.dispose();
  }

  Equipo get _draft => Equipo(clubId: widget.team.clubId, barras: _bars, discos: _plates);

  void _add(TextEditingController field, bool isBar) {
    final kg = _parseKg(field.text);
    if (kg == null || kg <= 0) return;
    setState(() {
      if (isBar) {
        _bars = _withOneMore(_bars, kg);
      } else {
        _plates = _withOneMore(_plates, kg);
      }
      field.clear();
    });
  }

  Future<void> _save() async {
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(catalogAdminRepositoryProvider).saveTeam(clubId, _draft);
      ref.invalidate(clubTeamProvider);
      if (mounted) showNotice(context, 'Equipo guardado.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section({
    required String title,
    required String prefix,
    required String unit,
    required List<ItemInventario> items,
    required ValueChanged<List<ItemInventario>> onChanged,
    required TextEditingController field,
    required bool isBar,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: context.textos.titleSmall),
      const SizedBox(height: Espacio.s),
      for (final item in items)
        Row(
          key: Key('$prefix-${formatKg(item.kg)}'),
          children: [
            Expanded(child: Text('${formatKg(item.kg)} kg', style: context.numeros.chico)),
            Text(unit, style: context.textos.bodySmall),
            const SizedBox(width: Espacio.s),
            ContadorCantidad(
              valor: item.cantidad,
              maximo: maxCantidadInventario,
              onChanged: widget.canEdit
                  ? (n) => onChanged([for (final i in items) i.kg == item.kg ? i.conCantidad(n) : i])
                  : null,
            ),
            if (widget.canEdit)
              IconButton(
                key: Key('$prefix-remove-${formatKg(item.kg)}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Quitar',
                onPressed: () => onChanged([for (final i in items) if (i.kg != item.kg) i]),
              ),
          ],
        ),
      if (widget.canEdit) ...[
        const SizedBox(height: Espacio.s),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: Key('team-$prefix-input'),
                controller: field,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Agregar peso (kg)'),
                onSubmitted: (_) => _add(field, isBar),
              ),
            ),
            const SizedBox(width: Espacio.s),
            IconButton.filledTonal(
              key: Key('team-$prefix-add'),
              onPressed: () => _add(field, isBar),
              icon: const Icon(Icons.add),
              tooltip: 'Agregar',
            ),
          ],
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problems = draft.validar();
    final bar = _bars.any((b) => b.kg == _previewBar) ? _previewBar! : draft.barraKg;
    final loadable = problems.isEmpty ? draft.cargablesCon(bar) : const <double>[];
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        _section(
          title: 'Barras',
          prefix: 'bar',
          unit: 'unidades',
          items: _bars,
          onChanged: (v) => setState(() => _bars = v),
          field: _bar,
          isBar: true,
        ),
        const SizedBox(height: Espacio.l),
        _section(
          title: 'Discos',
          prefix: 'plate',
          unit: 'pares',
          items: _plates,
          onChanged: (v) => setState(() => _plates = v),
          field: _plate,
          isBar: false,
        ),
        const SizedBox(height: Espacio.l),
        for (final p in problems)
          Text(_problemLabel(p), style: context.textos.bodyMedium?.copyWith(color: context.esquema.error)),
        if (widget.canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('team-save'),
              onPressed: problems.isEmpty && !_saving ? _save : null,
              child: const Text('Guardar equipo'),
            ),
          ),
        const SizedBox(height: Espacio.l),
        if (problems.isEmpty) ...[
          Text('Pesos cargables', style: context.textos.titleSmall),
          if (_bars.length > 1)
            Wrap(
              spacing: Espacio.s,
              children: [
                for (final b in _bars)
                  ChoiceChip(
                    key: Key('team-preview-bar-${formatKg(b.kg)}'),
                    label: Text('Barra ${formatKg(b.kg)}'),
                    selected: b.kg == bar,
                    onSelected: (_) => setState(() => _previewBar = b.kg),
                  ),
              ],
            ),
          Text('${loadable.length} pesos con este equipo', key: const Key('team-count')),
          const SizedBox(height: Espacio.s),
          Wrap(
            key: const Key('team-preview'),
            spacing: Espacio.m,
            runSpacing: Espacio.xs,
            children: [
              for (final kg in loadable) Text(formatKg(kg), style: context.numeros.chico),
            ],
          ),
        ],
      ],
    );
  }
}
