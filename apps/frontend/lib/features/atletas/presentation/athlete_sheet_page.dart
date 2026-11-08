import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/athlete_repository.dart';
import '../domain/reference_form_rules.dart';
import 'athlete_sheet_widgets.dart';
import 'reference_form_dialog.dart';
import 'providers.dart';

/// An athlete's references as the coach reads them (E3.5). The coach also gets the forms to record RMs, factors and fixed weights (E3.6).
class AthleteSheetPage extends ConsumerWidget {
  const AthleteSheetPage({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(athletesProvider)
        .value
        ?.where((a) => a.id == athleteId)
        .firstOrNull
        ?.name;
    final data = ref.watch(athleteSheetProvider(athleteId));
    final names = ref.watch(exerciseNamesProvider);
    // Both loads must finish; an error in either shows the backend's message.
    final combined = switch ((data, names)) {
      (AsyncError(:final error, :final stackTrace), _) =>
        AsyncError<(AthleteSheet, Map<String, String>)>(error, stackTrace),
      (_, AsyncError(:final error, :final stackTrace)) =>
        AsyncError<(AthleteSheet, Map<String, String>)>(error, stackTrace),
      (AsyncData(value: final sheet), AsyncData(value: final n)) =>
        AsyncData<(AthleteSheet, Map<String, String>)>((sheet, n)),
      _ => const AsyncLoading<(AthleteSheet, Map<String, String>)>(),
    };
    return Scaffold(
      appBar: AppBar(title: Text(name ?? 'Ficha del atleta')),
      body: asyncView(
        combined,
        onRetry: () {
          ref.invalidate(athleteSheetProvider(athleteId));
          ref.invalidate(exerciseNamesProvider);
        },
        builder: (v) {
          final today = ref.watch(todayProvider);
          final view = AthleteSheetView(
            sheet: v.$1,
            exerciseNames: v.$2,
            today: today,
          );
          if (!ref.watch(canEditReferencesProvider)) return view;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacio.l,
                  Espacio.m,
                  Espacio.l,
                  0,
                ),
                child: Wrap(
                  spacing: Espacio.s,
                  runSpacing: Espacio.s,
                  children: [
                    for (final (kind, label, icon) in const [
                      (ReferenceKind.rm, 'Cargar RM', Icons.add),
                      (ReferenceKind.factor, 'Cargar factor', Icons.percent),
                      (ReferenceKind.fixedWeight, 'Fijar kilaje', Icons.lock_outline),
                    ])
                      OutlinedButton.icon(
                        key: Key('edit-${kind.name}'),
                        onPressed: () => _openForm(context, ref, kind, today),
                        icon: Icon(icon),
                        label: Text(label),
                      ),
                  ],
                ),
              ),
              Expanded(child: view),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    ReferenceKind kind,
    DateTime today,
  ) async {
    final clubId = ref.read(meProvider).value?.activeClub?.club.id;
    if (clubId == null) return;
    final repo = ref.read(athleteRepositoryProvider);
    final saved = await showReferenceForm(
      context,
      kind: kind,
      today: today,
      onSave: (exercise, value, date) => switch (kind) {
        ReferenceKind.rm => repo.addReference(
          clubId,
          athleteId,
          exerciseId: exercise.id,
          value: value,
          date: date!,
        ),
        ReferenceKind.factor => repo.addFactor(
          clubId,
          athleteId,
          exerciseId: exercise.id,
          percent: value,
          date: date!,
        ),
        ReferenceKind.fixedWeight => repo.setFixedWeight(
          clubId,
          athleteId,
          exerciseId: exercise.id,
          kg: value,
        ),
      },
    );
    if (saved) ref.invalidate(athleteSheetProvider(athleteId));
  }
}
