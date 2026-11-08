import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart' show canPlanProvider;
import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show SectionTitle, asyncView;
import '../../plan/presentation/plan_labels.dart' show setsSummary;
import 'calendar_providers.dart';

/// The plan's calendar, read-only: opens on the cycle and week the backend gives for today, on day 1 of that
/// week, and lets the user pick another week and day. [assignmentsPath] is where a coach goes to assign a plan.
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key, required this.assignmentsPath});

  final String assignmentsPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(calendarProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(calendarProvider),
        builder: (data) => data.hasPlan
            ? _Calendar(data: data)
            : _NoAssignment(
                canAssign: ref.watch(canPlanProvider) ?? false,
                assignmentsPath: assignmentsPath,
              ),
      ),
    );
  }
}

class _NoAssignment extends StatelessWidget {
  const _NoAssignment({required this.canAssign, required this.assignmentsPath});

  final bool canAssign;
  final String assignmentsPath;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Espacio.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Espacio.m,
        children: [
          Text(
            'Todavía no hay un plan asignado',
            key: const Key('calendar-empty'),
            style: context.textos.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (canAssign)
            FilledButton(
              key: const Key('calendar-go-assignments'),
              onPressed: () => context.go(assignmentsPath),
              child: const Text('Ir a Asignaciones'),
            ),
        ],
      ),
    ),
  );
}

class _Calendar extends ConsumerWidget {
  const _Calendar({required this.data});

  final CalendarData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = data.location!;
    final plan = data.plan!;
    final picked = ref.watch(calendarSelectionProvider);
    final week = picked?.week ?? location.week;
    final model = plan.weekModelOf(week);
    final dayCount = model?.days.length ?? 0;
    final day = (picked?.day ?? 1).clamp(1, dayCount < 1 ? 1 : dayCount);
    final notifier = ref.read(calendarSelectionProvider.notifier);
    final planDay = model != null && day <= dayCount
        ? model.days[day - 1]
        : null;

    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Text(
          '${plan.name} · ciclo ${location.cycle} · semana ${location.week}',
          key: const Key('calendar-today'),
          style: context.textos.titleMedium,
        ),
        const SizedBox(height: Espacio.m),
        Text('Semana', style: context.textos.labelLarge),
        const SizedBox(height: Espacio.s),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (var w = 1; w <= 4; w++)
              PildoraMaktub(
                key: Key('calendar-week-$w'),
                texto: 'S$w',
                detalle: plan.weekModelOf(w)?.name,
                seleccionada: w == week,
                onTap: () => notifier.selectWeek(w),
              ),
          ],
        ),
        const SizedBox(height: Espacio.m),
        Text('Día', style: context.textos.labelLarge),
        const SizedBox(height: Espacio.s),
        if (dayCount == 0)
          Text(
            'Esta semana no tiene días cargados.',
            key: const Key('calendar-no-days'),
            style: context.textos.bodyMedium,
          )
        else
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            children: [
              for (var d = 1; d <= dayCount; d++)
                PildoraMaktub(
                  key: Key('calendar-day-$d'),
                  texto: 'Día $d',
                  seleccionada: d == day,
                  onTap: () => notifier.selectDay(week, d),
                ),
            ],
          ),
        if (planDay != null) ...[
          const SizedBox(height: Espacio.l),
          Text(
            planDay.name == null || planDay.name!.isEmpty
                ? 'Día $day'
                : 'Día $day · ${planDay.name}',
            key: const Key('calendar-day-title'),
            style: context.textos.titleLarge,
          ),
          if (planDay.blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Espacio.s),
              child: Text(
                'Este día no tiene bloques.',
                key: const Key('calendar-no-blocks'),
                style: context.textos.bodyMedium,
              ),
            ),
          for (final block in planDay.blocks)
            _Block(block: block, names: data.exerciseNames),
        ],
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, required this.names});

  final PlanBlock block;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle(block.name),
      if (block.note != null)
        Text(block.note!, style: context.textos.bodyMedium),
      for (final p in block.prescriptions)
        _PrescriptionRow(prescription: p, names: names),
    ],
  );
}

class _PrescriptionRow extends StatelessWidget {
  const _PrescriptionRow({required this.prescription, required this.names});

  final Prescription prescription;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final id = prescription.exerciseId;
    final name = id == null ? 'Sin ejercicio' : names[id] ?? 'Ejercicio';
    final sets = setsSummary(prescription.sets);
    final note = prescription.note;
    final detail = [
      if (sets.isNotEmpty) sets,
      if (note != null && note.isNotEmpty) note,
    ].join(' · ');
    return ListTile(
      title: Text(name),
      subtitle: detail.isEmpty ? null : Text(detail),
    );
  }
}
