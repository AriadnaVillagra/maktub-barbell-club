import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../access/presentation/providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../domain/athlete_repository.dart';
import 'athlete_sheet_widgets.dart';
import 'providers.dart';

/// The athlete's own RMs (E3.8), with the one in force today marked. Work factors and fixed weights
/// are the coach's, so they don't show here, even for a user who is also a coach; that user sees and
/// edits them in the athlete sheet (E3.6).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athleteId = ref.watch(meProvider).value?.athleteId;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: athleteId == null
          ? const SizedBox.shrink()
          : _Body(athleteId: athleteId),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return asyncView(
      combined,
      onRetry: () {
        ref.invalidate(athleteSheetProvider(athleteId));
        ref.invalidate(exerciseNamesProvider);
      },
      builder: (v) => AthleteSheetView(
        sheet: v.$1,
        exerciseNames: v.$2,
        today: ref.watch(todayProvider),
        emptyMessage: 'Todavía no tenés RMs cargados.',
        rmOnly: true,
      ),
    );
  }
}
