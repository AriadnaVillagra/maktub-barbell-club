import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'providers.dart';

/// The club's equipment: bar and plate pairs, with a live preview of the loadable weights they give.
/// Coaches edit; anyone else only sees the equipment and its weights (F2 §6, "Equipo").
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
          : _TeamEditor(
              team: team,
              canEdit: ref.watch(canPlanProvider) ?? false,
            ),
    ),
  );
}

String _problemLabel(EquipoProblem p) => switch (p) {
  EquipoProblem.barNotPositive => 'La barra debe pesar más de 0.',
  EquipoProblem.plateNotPositive => 'Todos los discos deben pesar más de 0.',
  EquipoProblem.duplicatePlate => 'Hay dos pares del mismo peso.',
  EquipoProblem.tooManyPlates =>
    'Un equipo admite hasta $maxParesDiscos pares de discos.',
};

double? _parseKg(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class _TeamEditor extends ConsumerStatefulWidget {
  const _TeamEditor({required this.team, required this.canEdit});

  final Equipo team;
  final bool canEdit;

  @override
  ConsumerState<_TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends ConsumerState<_TeamEditor> {
  late final _bar = TextEditingController(text: formatKg(widget.team.barraKg));
  final _plate = TextEditingController();
  late List<double> _plates = [...widget.team.paresDiscos];
  bool _saving = false;

  @override
  void dispose() {
    _bar.dispose();
    _plate.dispose();
    super.dispose();
  }

  /// The equipment being edited. A bar that doesn't parse counts as 0, which [Equipo.validar] reports.
  Equipo get _draft => Equipo(
    clubId: widget.team.clubId,
    barraKg: _parseKg(_bar.text) ?? 0,
    paresDiscos: _plates,
  );

  void _addPlate() {
    final kg = _parseKg(_plate.text);
    if (kg == null) return;
    setState(() {
      _plates = [..._plates, kg]..sort((a, b) => b.compareTo(a));
      _plate.clear();
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

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problems = draft.validar();
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        TextField(
          key: const Key('team-bar'),
          controller: _bar,
          enabled: widget.canEdit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Barra (kg)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Espacio.l),
        Text(
          'Pares de discos (kg, uno por lado)',
          style: context.textos.titleSmall,
        ),
        const SizedBox(height: Espacio.s),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (final (i, kg) in _plates.indexed)
              InputChip(
                // A duplicate (invalid, reported below) has no key: keys must be unique among siblings.
                key: _plates.indexOf(kg) == i ? Key('plate-${formatKg(kg)}') : null,
                label: Text(formatKg(kg)),
                onDeleted: widget.canEdit
                    ? () => setState(() => _plates = [..._plates]..remove(kg))
                    : null,
              ),
          ],
        ),
        if (widget.canEdit) ...[
          const SizedBox(height: Espacio.m),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('team-plate-input'),
                  controller: _plate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Agregar par (kg)',
                  ),
                  onSubmitted: (_) => _addPlate(),
                ),
              ),
              const SizedBox(width: Espacio.s),
              IconButton.filledTonal(
                key: const Key('team-plate-add'),
                onPressed: _addPlate,
                icon: const Icon(Icons.add),
                tooltip: 'Agregar disco',
              ),
            ],
          ),
        ],
        const SizedBox(height: Espacio.l),
        for (final p in problems)
          Text(
            _problemLabel(p),
            style: context.textos.bodyMedium?.copyWith(
              color: context.esquema.error,
            ),
          ),
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
          Text(
            '${draft.cargables.length} pesos con este equipo',
            key: const Key('team-count'),
          ),
          const SizedBox(height: Espacio.s),
          Wrap(
            key: const Key('team-preview'),
            spacing: Espacio.m,
            runSpacing: Espacio.xs,
            children: [
              for (final kg in draft.cargables)
                Text(formatKg(kg), style: context.numeros.chico),
            ],
          ),
        ],
      ],
    );
  }
}
