import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/red/cliente_api.dart';
import '../../access/presentation/providers.dart';
import '../../atletas/presentation/providers.dart' show athletesProvider;
import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../domain/history_labels.dart';
import 'providers.dart';

/// An athlete's past sessions by date, newest first, from any plan (pedido de Ari, 2026-11-21). Read-only; tapping
/// one opens its detail at `<basePath>/<sessionId>`. Older sessions come with "Cargar más".
class AthleteHistoryPage extends ConsumerWidget {
  const AthleteHistoryPage({
    super.key,
    required this.athleteId,
    required this.basePath,
    this.athleteName,
  });

  final String athleteId;

  /// The route of this page.
  final String basePath;

  /// Shown in the title when someone else's history is read (the coach's way in).
  final String? athleteName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = historyListProvider(athleteId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          athleteName == null ? 'Historial' : 'Historial de $athleteName',
        ),
      ),
      body: asyncView(
        ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        builder: (list) => list.entries.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(Espacio.l),
                  child: Text(
                    'Todavía no hay sesiones en el historial.',
                    key: Key('history-empty'),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(provider.future),
                child: ListView(
                  key: const Key('history-list'),
                  padding: const EdgeInsets.only(bottom: Espacio.xl),
                  children: [
                    for (final (i, e) in list.entries.indexed) ...[
                      if (i == 0 ||
                          !_sameMonth(list.entries[i - 1].date, e.date))
                        _MonthHeader(e.date),
                      _EntryTile(
                        entry: e,
                        onTap: () => context.go(
                          '$basePath/${Uri.encodeComponent(e.sessionId)}',
                        ),
                      ),
                    ],
                    if (list.hasMore || list.moreError != null)
                      _LoadMore(
                        loading: list.loadingMore,
                        error: list.moreError,
                        onPressed: () => ref.read(provider.notifier).loadMore(),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}

/// An athlete's history as the coach reads it, from the athlete sheet: the title carries the athlete's name.
class CoachHistoryPage extends ConsumerWidget {
  const CoachHistoryPage({
    super.key,
    required this.athleteId,
    required this.basePath,
  });

  final String athleteId;
  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(athletesProvider)
        .value
        ?.where((a) => a.id == athleteId)
        .firstOrNull
        ?.name;
    return AthleteHistoryPage(
      athleteId: athleteId,
      basePath: basePath,
      athleteName: name,
    );
  }
}

/// The signed-in user's own history, as the athlete of the active club.
class OwnHistoryPage extends ConsumerWidget {
  const OwnHistoryPage({super.key, required this.basePath});

  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athleteId = ref.watch(meProvider).value?.athleteId;
    if (athleteId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Historial')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return AthleteHistoryPage(athleteId: athleteId, basePath: basePath);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Espacio.l,
      Espacio.l,
      Espacio.l,
      Espacio.xs,
    ),
    child: Text(historyMonthLabel(date), style: context.textos.titleSmall),
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return ListTile(
      key: Key('history-${e.sessionId}'),
      title: Text(historyPlanLabel(e)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Espacio.xs,
        children: [
          Text('${historyDateLabel(e.date)} · ${historyPositionLabel(e)}'),
          Wrap(
            spacing: Espacio.xs,
            runSpacing: Espacio.xs,
            children: entryBadges(context, e),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// The badges of a session: its sets done out of the total, estimated sets and a historical plan.
List<Widget> entryBadges(BuildContext context, HistoryEntry e) => [
  InsigniaMaktub(
    '${e.done}/${e.total} series',
    e.total > 0 && e.done >= e.total
        ? context.colores.exitoContenedor
        : context.colores.insigniaBase,
    icono: e.total > 0 && e.done >= e.total ? Icons.check : null,
  ),
  if (e.estimated > 0)
    InsigniaMaktub(
      e.estimated == 1 ? '1 estimada' : '${e.estimated} estimadas',
      context.colores.alertaContenedor,
      icono: Icons.auto_awesome_outlined,
    ),
  if (e.planType == PlanType.history)
    InsigniaMaktub('Histórico', context.colores.insigniaBase),
];

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final bool loading;
  final Object? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Espacio.l),
    child: Column(
      spacing: Espacio.s,
      children: [
        if (error != null)
          Text(
            error is ErrorDeApi
                ? (error! as ErrorDeApi).mensaje
                : 'No se pudo cargar.',
            key: const Key('history-more-error'),
            style: context.textos.bodyMedium!.copyWith(
              color: context.esquema.error,
            ),
          ),
        if (loading)
          const CircularProgressIndicator()
        else
          OutlinedButton(
            key: const Key('history-more'),
            onPressed: onPressed,
            child: Text(error == null ? 'Cargar más' : 'Reintentar'),
          ),
      ],
    ),
  );
}
