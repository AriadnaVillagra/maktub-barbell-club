import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/app_version.dart';
import '../../access/presentation/providers.dart';
import '../../access/presentation/role_labels.dart';
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Identity(),
          const Divider(),
          if (athleteId != null) Expanded(child: _Body(athleteId: athleteId)),
        ],
      ),
    );
  }
}

/// Who is signed in, what they can do in the active club, and which build of the app is running.
class _Identity extends ConsumerWidget {
  const _Identity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const SizedBox.shrink();
    final roles = me.activeClub?.roles ?? const <Rol>{};
    return Padding(
      padding: const EdgeInsets.all(Espacio.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Espacio.xs,
        children: [
          Text(me.user.nombre, style: context.textos.titleLarge),
          Text(me.user.email, style: context.textos.bodyMedium),
          Wrap(
            spacing: Espacio.xs,
            runSpacing: Espacio.xs,
            children: [
              for (final role in Rol.values)
                if (roles.contains(role))
                  InsigniaMaktub(roleLabel(role), context.colores.insigniaBase),
              if (me.isPlatformAdmin)
                InsigniaMaktub(
                  'Admin de plataforma',
                  context.colores.insigniaPropio,
                ),
            ],
          ),
          Text(
            'Versión $appVersion',
            key: const Key('profile-version'),
            style: context.textos.labelSmall,
          ),
        ],
      ),
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
