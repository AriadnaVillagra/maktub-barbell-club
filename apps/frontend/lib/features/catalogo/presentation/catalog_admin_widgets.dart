import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/catalog_filters.dart';

/// Shows the message of an API error (or a generic one) in a snack bar.
void showApiError(BuildContext context, Object error) {
  final message = error is ErrorDeApi
      ? error.mensaje
      : 'No se pudo completar la acción.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showNotice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

/// Asks for confirmation before a destructive action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Section title of a list.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Espacio.l,
      Espacio.l,
      Espacio.l,
      Espacio.xs,
    ),
    child: Text(text, style: context.textos.titleSmall),
  );
}

/// Loading, error (with retry) or data of a screen.
Widget asyncView<T>(
  AsyncValue<T> value, {
  required VoidCallback onRetry,
  required Widget Function(T) builder,
}) => value.when(
  data: builder,
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Espacio.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e is ErrorDeApi ? e.mensaje : 'No se pudo cargar.'),
          const SizedBox(height: Espacio.m),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  ),
);

/// Formats a weight without a trailing ".0": 20 → "20", 2.5 → "2.5".
String formatKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : '$kg';

/// "Default" or "Custom", so the origin of an entry is clear at a glance.
class ScopeBadge extends StatelessWidget {
  const ScopeBadge(this.scope, {super.key});

  final CatalogScope scope;

  @override
  Widget build(BuildContext context) => scope == CatalogScope.base
      ? InsigniaMaktub('Default', context.colores.insigniaBase)
      : InsigniaMaktub('Custom', context.colores.insigniaPropio);
}

/// The filters shared by the management lists: origin and archived.
class CatalogFilters extends StatelessWidget {
  const CatalogFilters({
    super.key,
    required this.scope,
    required this.onScope,
    required this.showArchived,
    required this.onShowArchived,
    required this.archivedLabel,
  });

  final ScopeFilter scope;
  final ValueChanged<ScopeFilter> onScope;
  final bool showArchived;
  final ValueChanged<bool> onShowArchived;
  final String archivedLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.m, Espacio.m, 0),
        child: Wrap(
          spacing: Espacio.s,
          children: [
            for (final (value, label) in const [
              (ScopeFilter.all, 'Todas'),
              (ScopeFilter.base, 'Default'),
              (ScopeFilter.club, 'Custom'),
            ])
              ChoiceChip(
                key: Key('scope-${value.name}'),
                label: Text(label),
                selected: scope == value,
                onSelected: (_) => onScope(value),
              ),
          ],
        ),
      ),
      SwitchListTile(
        key: const Key('show-archived'),
        title: Text(archivedLabel),
        value: showArchived,
        onChanged: onShowArchived,
      ),
    ],
  );
}
