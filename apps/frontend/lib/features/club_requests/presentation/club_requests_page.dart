import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/refresh/refresh_on_return.dart';
import '../../access/presentation/providers.dart' show isPlatformAdminProvider;
import '../../catalogo/presentation/catalog_admin_widgets.dart';
import 'providers.dart';

String _day(DateTime instant) {
  final d = instant.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// The pending club requests, for platform admins: approving one creates the club and the requester's
/// account; rejecting it tells the requester on their next sign-in.
class ClubRequestsPage extends ConsumerWidget {
  const ClubRequestsPage({super.key});

  Future<void> _approve(BuildContext context, WidgetRef ref, ClubRequest request) async {
    final ok = await confirmAction(
      context,
      title: 'Aprobar "${request.clubName}"',
      body: 'Se crea el club y ${request.requesterName} (${request.email}) queda como administrador, coach y atleta.',
      action: 'Aprobar',
    );
    if (!ok || !context.mounted) return;
    try {
      final club = await ref.read(clubRequestsRepositoryProvider).approve(request.id);
      ref.invalidate(pendingClubRequestsProvider);
      if (context.mounted) showNotice(context, 'Club "${club.nombre}" creado.');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, ClubRequest request) async {
    final ok = await confirmAction(
      context,
      title: 'Rechazar "${request.clubName}"',
      body: '${request.requesterName} va a ver que su pedido no fue aprobado la próxima vez que ingrese.',
      action: 'Rechazar',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(clubRequestsRepositoryProvider).reject(request.id);
      ref.invalidate(pendingClubRequestsProvider);
      if (context.mounted) showNotice(context, 'Pedido rechazado.');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isPlatformAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedidos de clubes')),
        body: const Center(child: Text('Solo un administrador de plataforma ve los pedidos de clubes.')),
      );
    }
    return RefreshOnReturn(
      // Another admin may have reviewed some meanwhile.
      providers: [pendingClubRequestsProvider],
      child: Scaffold(
        appBar: AppBar(title: const Text('Pedidos de clubes')),
        body: asyncView(
          ref.watch(pendingClubRequestsProvider),
          onRetry: () => ref.invalidate(pendingClubRequestsProvider),
          builder: (requests) => requests.isEmpty
              ? const Center(child: Text('No hay pedidos pendientes.'))
              : ListView(
                  padding: const EdgeInsets.all(Espacio.l),
                  children: [
                    for (final r in requests)
                      Card(
                        key: Key('club-request-${r.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(Espacio.l),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Espacio.s,
                            children: [
                              Text(r.clubName, style: context.textos.titleMedium),
                              Text('${r.requesterName} · ${r.email}', style: context.textos.bodyMedium),
                              if (r.note != null) Text(r.note!, style: context.textos.bodyMedium),
                              Text(
                                'Pedido el ${_day(r.auditoria.creadoEn)}',
                                style: context.textos.bodySmall?.copyWith(color: context.esquema.onSurfaceVariant),
                              ),
                              OverflowBar(
                                alignment: MainAxisAlignment.end,
                                spacing: Espacio.s,
                                children: [
                                  TextButton(
                                    key: Key('club-request-reject-${r.id}'),
                                    onPressed: () => _reject(context, ref, r),
                                    child: const Text('Rechazar'),
                                  ),
                                  FilledButton(
                                    key: Key('club-request-approve-${r.id}'),
                                    onPressed: () => _approve(context, ref, r),
                                    child: const Text('Aprobar'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
