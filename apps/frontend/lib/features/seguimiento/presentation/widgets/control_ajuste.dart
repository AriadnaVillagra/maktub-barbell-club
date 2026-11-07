import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';

/// −5 % / +5 % con el valor en el medio, y "reset" cuando hay algo que deshacer.
class ControlAjuste extends StatelessWidget {
  const ControlAjuste({
    super.key,
    required this.titulo,
    required this.valor,
    required this.onCambio,
    this.propio = false,
  });

  final String titulo;
  final int valor;

  /// Recibe el delta; 0 significa volver al valor heredado.
  final ValueChanged<int> onCambio;

  /// Si el valor es propio (no heredado), también se puede resetear estando en 100.
  final bool propio;

  @override
  Widget build(BuildContext context) {
    final cambiado = valor != Ajuste.neutro;
    final esquema = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(titulo, style: Theme.of(context).textTheme.bodyMedium)),
        IconButton.outlined(
          tooltip: '−${Ajuste.paso}%',
          onPressed: () => onCambio(-Ajuste.paso),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$valor%',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: cambiado ? esquema.tertiary : null),
          ),
        ),
        IconButton.outlined(
          tooltip: '+${Ajuste.paso}%',
          onPressed: () => onCambio(Ajuste.paso),
          icon: const Icon(Icons.add),
        ),
        if (cambiado || propio) TextButton(onPressed: () => onCambio(0), child: const Text('reset')),
      ],
    );
  }
}
