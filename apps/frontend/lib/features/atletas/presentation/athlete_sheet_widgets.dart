import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show formatKg;
import '../domain/athlete_repository.dart';
import '../domain/sheet_rows.dart';

/// "08/11/2026" from a calendar date.
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _percent(double value) => '${formatKg(value)} %';

/// Read-only view of an athlete's references: one card per exercise, with the RM in force today
/// marked. Shared by the coach's sheet (E3.5) and the athlete's Perfil tab (E3.8).
class AthleteSheetView extends StatelessWidget {
  const AthleteSheetView({
    super.key,
    required this.sheet,
    required this.exerciseNames,
    required this.today,
    this.emptyMessage = 'Este atleta todavía no tiene referencias.',
    this.rmOnly = false,
    this.onlyExerciseIds,
  });

  final AthleteSheet sheet;

  /// When given, only these exercises are shown.
  final Set<String>? onlyExerciseIds;

  /// Shows only the RMs, for the athlete's own view: factors and fixed weights are the coach's.
  final bool rmOnly;

  /// Shown when there is nothing recorded yet.
  final String emptyMessage;

  /// Exercise names by id.
  final Map<String, String> exerciseNames;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final shown = rmOnly
        ? AthleteSheet(athleteId: sheet.athleteId, references: sheet.references)
        : sheet;
    final only = onlyExerciseIds;
    final rows = sheetRows(shown, today: today)
      ..removeWhere((r) => only != null && !only.contains(r.exerciseId))
      ..sort(
        (a, b) =>
            _name(a.exerciseId)
                .toLowerCase()
                .compareTo(_name(b.exerciseId).toLowerCase()),
      );
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Text(
            emptyMessage,
            key: const Key('sheet-empty'),
            style: context.textos.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        for (final row in rows)
          ExerciseReferenceCard(
            key: Key('sheet-exercise-${row.exerciseId}'),
            name: _name(row.exerciseId),
            row: row,
            rmOnly: rmOnly,
          ),
      ],
    );
  }

  String _name(String id) => exerciseNames[id] ?? 'Ejercicio desconocido';
}

/// RM history, work factor and fixed weight of one exercise.
class ExerciseReferenceCard extends StatelessWidget {
  const ExerciseReferenceCard({
    super.key,
    required this.name,
    required this.row,
    this.rmOnly = false,
  });

  final String name;
  final ExerciseSheetRow row;
  final bool rmOnly;

  @override
  Widget build(BuildContext context) {
    final text = context.textos;
    return Card(
      margin: const EdgeInsets.only(bottom: Espacio.m),
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Espacio.s,
          children: [
            Text(name, style: text.titleMedium),
            if (row.rms.isNotEmpty) ...[
              Text('RM', style: text.labelLarge),
              for (final rm in row.rms)
                _RmLine(rm: rm, current: identical(rm, row.currentRm)),
            ],
            if (!rmOnly) ...[
              Text('Factor de trabajo', style: text.labelLarge),
              Text(
                'Vigente: ${_percent(row.factor)}',
                key: Key('factor-current-${row.exerciseId}'),
              ),
              for (final f in row.factors)
                Text(
                  '${_percent(f.value)} desde ${formatDate(f.date)}',
                  key: Key('factor-${f.id}'),
                  style: text.bodySmall,
                ),
            ],
            if (!rmOnly && row.fixedWeight != null) ...[
              Text('Kilaje fijo', style: text.labelLarge),
              Text(
                '${formatKg(row.fixedWeight!.kg)} kg',
                key: Key('fixed-${row.exerciseId}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RmLine extends StatelessWidget {
  const _RmLine({required this.rm, required this.current});

  final Reference rm;
  final bool current;

  @override
  Widget build(BuildContext context) => Row(
    key: Key('rm-${rm.id}'),
    spacing: Espacio.s,
    children: [
      Text('${formatKg(rm.value)} kg', style: context.numeros.chico),
      Text('desde ${formatDate(rm.date)}'),
      if (current) InsigniaMaktub('Vigente', context.colores.exitoContenedor),
    ],
  );
}
