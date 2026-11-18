import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// One problem of a [ListaDeProblemas]: [mensaje] says what is wrong and [ubicacion], when there is one,
/// where it is ("Modelo A › Día 2 › Bloque 1").
class ProblemaMaktub {
  const ProblemaMaktub(this.mensaje, {this.ubicacion});

  final String mensaje;
  final String? ubicacion;
}

/// Error notice with a title and the complete list of what went wrong, for forms that refuse to
/// save (every problem at once, not just the first). Announced to screen readers when it appears.
///
/// With [plegarDesde], a list of that many problems or more starts closed: the title and a "Ver detalle"
/// button that opens it, so a long list does not push the screen down. Shorter lists always show.
class ListaDeProblemas extends StatefulWidget {
  const ListaDeProblemas({
    super.key,
    required this.titulo,
    this.problemas = const [],
    this.plegarDesde,
  });

  final String titulo;
  final List<ProblemaMaktub> problemas;

  /// How many problems make the list start closed; null shows them always.
  final int? plegarDesde;

  @override
  State<ListaDeProblemas> createState() => _ListaDeProblemasState();
}

class _ListaDeProblemasState extends State<ListaDeProblemas> {
  bool _abierta = false;

  bool get _plegable =>
      widget.plegarDesde != null &&
      widget.problemas.length >= widget.plegarDesde!;

  @override
  Widget build(BuildContext context) {
    final color = context.esquema.onErrorContainer;
    final visibles = !_plegable || _abierta;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.m),
        decoration: BoxDecoration(
          color: context.esquema.errorContainer,
          borderRadius: const BorderRadius.all(Radius.circular(Radios.medio)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: Espacio.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.titulo,
                    style: context.textos.titleSmall?.copyWith(color: color),
                  ),
                  if (visibles)
                    for (final p in widget.problemas)
                      Padding(
                        padding: const EdgeInsets.only(top: Espacio.s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.ubicacion != null)
                              Text(
                                p.ubicacion!,
                                style: context.textos.labelMedium?.copyWith(
                                  color: color,
                                ),
                              ),
                            Text(
                              p.mensaje,
                              style: context.textos.bodyMedium?.copyWith(
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                  if (_plegable)
                    TextButton.icon(
                      key: const Key('lista-de-problemas-detalle'),
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => setState(() => _abierta = !_abierta),
                      icon: Icon(
                        _abierta ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        _abierta
                            ? 'Ocultar detalle'
                            : 'Ver detalle (${widget.problemas.length})',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
