import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../domain/athlete_repository.dart';
import 'athlete_sheet_widgets.dart';
import 'providers.dart';

/// An athlete's references as the coach reads them (E3.5). Edit controls arrive with E3.6.
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
        builder: (v) => AthleteSheetView(
          sheet: v.$1,
          exerciseNames: v.$2,
          today: ref.watch(todayProvider),
        ),
      ),
    );
  }
}
