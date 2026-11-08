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
  });

  final AthleteSheet sheet;

  /// Exercise names by id.
  final Map<String, String> exerciseNames;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rows = sheetRows(sheet, today: today)
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
            'Este atleta todavía no tiene referencias.',
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
  });

  final String name;
  final ExerciseSheetRow row;

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
            if (row.fixedWeight != null) ...[
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
